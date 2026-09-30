module DataSources
  # 数据质量体检：把「看起来没报错但实际不对」的数据挑出来，落 DataQualityIssue 台账
  #
  # 覆盖两类数据：
  #   - 月K：缺月、后复权因子下降（应只增不改）、前后复权常数关系偏离
  #   - 财务：同一报告期只入库了部分子表、关键字段全空、报告日在未来
  # 「数值溢出被置空」不在这里扫描，由 BaseFetcher 写入时实时上报。
  class DataQualityService
    # 财务四张子表：完整的一期财务数据应四表齐全
    CHILD_MODELS = {
      "income_statement" => IncomeStatement,
      "balance_sheet" => BalanceSheet,
      "cash_flow" => CashFlow,
      "financial_indicator" => FinancialIndicator
    }.freeze

    class << self
      # 全量/按市场扫描；结果写入 DataQualityIssue（同一问题只保留一条未处理记录）
      def scan(market: nil, data_type: nil, limit: nil)
        types = data_type.present? ? [ data_type.to_s ] : %w[monthly_bar financial]
        scopes = types.index_with { |type| target_scope(market: market, data_type: type) }
        scopes.transform_values! { |scope| limit.present? ? scope.limit(limit.to_i) : scope }
        # 覆盖的股票集合与 CrawlerJob 的默认范围不同（只扫有数据的股票），此处用真实数量纠正进度分母
        CrawlContext.current&.start!(total_count: scopes.values.sum(&:count))

        stats = { checked: 0, issues: 0 }
        scopes.each do |type, scope|
          Rails.logger.info "[DataQualityService] 开始扫描 #{type}，共 #{scope.count} 只股票"

          scope.find_each do |stock|
            found = type == "monthly_bar" ? check_monthly_bars(stock) : check_financials(stock)
            stats[:checked] += 1
            stats[:issues] += found
            CrawlContext.current&.tick(unit_id: stock.id, ok: true)
          end
        end

        Rails.logger.info "[DataQualityService] 扫描完成：检查 #{stats[:checked]} 只，检出 #{stats[:issues]} 项问题"
        stats
      end

      # ── 月K ──
      # 返回检出的问题条数
      def check_monthly_bars(stock)
        bars = stock.stock_monthly_bars.chronological.pluck(:trade_date, :hfq_factor, :hfq_close, :qfq_close)
        return 0 if bars.size < 2

        issues = 0
        issues += 1 if record_month_gap(stock, bars)
        issues += 1 if record_factor_decrease(stock, bars)
        issues += 1 if record_ratio_deviation(stock, bars)
        issues
      end

      # ── 财务 ──
      def check_financials(stock)
        report_dates = stock.financial_reports.pluck(:report_date).compact.uniq
        return 0 if report_dates.empty?

        issues = 0
        issues += 1 if record_partial_period(stock, report_dates)
        issues += 1 if record_empty_financials(stock, report_dates)
        issues += 1 if record_future_report_date(stock, report_dates)
        issues
      end

      private

      # 只扫描「确有数据」的股票，避免把空数据当成质量问题刷屏
      def target_scope(market:, data_type:)
        scope = market.present? ? Stock.where(market: market) : Stock.all
        case data_type
        when "monthly_bar"
          scope.where(id: StockMonthlyBar.select(:stock_id))
        when "financial"
          scope.where(id: FinancialReport.select(:stock_id))
        else
          scope
        end
      end

      # 相邻两个月K行之间月份差 > 1（整月停牌会误报，detail 里记区间供人工复核）
      def record_month_gap(stock, bars)
        bars.each_cons(2) do |(prev_date, *), (date, *)|
          gap = (date.year * 12 + date.month) - (prev_date.year * 12 + prev_date.month)
          next if gap <= 1

          DataQualityIssue.record!(
            stock, "monthly_bar", "month_gap",
            severity: "warning",
            detail: { from: prev_date.to_s, to: date.to_s, missing_months: gap - 1 }
          )
          return true
        end
        false
      end

      # 后复权因子只增不改：出现下降说明复权口径被写坏
      def record_factor_decrease(stock, bars)
        bars.each_cons(2) do |(prev_date, prev_factor, *), (date, factor, *)|
          next if prev_factor.nil? || factor.nil?
          next if factor.to_d >= prev_factor.to_d

          DataQualityIssue.record!(
            stock, "monthly_bar", "hfq_factor_decrease",
            severity: "error",
            detail: {
              from: prev_date.to_s, to: date.to_s,
              prev_factor: prev_factor.to_s, factor: factor.to_s
            }
          )
          return true
        end
        false
      end

      # 同一只股票任意两行的 后复权收盘 ÷ 前复权收盘 必须是同一常数
      def record_ratio_deviation(stock, bars)
        ratios = bars.filter_map do |(date, _factor, hfq_close, qfq_close)|
          next if hfq_close.blank? || qfq_close.to_d.zero?

          [ date, hfq_close.to_d / qfq_close.to_d ]
        end
        return false if ratios.size < 2

        expected = ratios.first.last
        date, ratio = ratios.max_by { |(_d, r)| ((r - expected) / expected).abs }
        deviation = ((ratio - expected) / expected).abs
        return false if deviation <= SinaMonthlyBarService::RATIO_TOLERANCE

        DataQualityIssue.record!(
          stock, "monthly_bar", "ratio_deviation",
          severity: "error",
          detail: { sample_date: date.to_s, expected_ratio: expected.to_s, actual_ratio: ratio.to_s,
                    max_deviation: deviation.to_f }
        )
        true
      end

      # 同一报告期只入库了部分子表
      def record_partial_period(stock, report_dates)
        present = child_report_dates(stock)
        report_dates.sort.reverse_each do |date|
          tables = present.keys.select { |name| present[name].include?(date) }
          next if tables.size.zero? || tables.size == CHILD_MODELS.size

          DataQualityIssue.record!(
            stock, "financial", "partial_period",
            severity: "warning",
            detail: { report_date: date.to_s, present_tables: tables,
                      missing_tables: CHILD_MODELS.keys - tables }
          )
          return true
        end
        false
      end

      # 营收与总资产同时为空（两表都有行但关键字段全空）
      def record_empty_financials(stock, report_dates)
        revenue = IncomeStatement.where(stock_id: stock.id).pluck(:report_date, :total_revenue).to_h
        assets = BalanceSheet.where(stock_id: stock.id).pluck(:report_date, :total_assets).to_h

        report_dates.sort.reverse_each do |date|
          next unless revenue.key?(date) && assets.key?(date)
          next unless revenue[date].blank? && assets[date].blank?

          DataQualityIssue.record!(
            stock, "financial", "empty_financials",
            severity: "warning",
            detail: { report_date: date.to_s, total_revenue: nil, total_assets: nil }
          )
          return true
        end
        false
      end

      def record_future_report_date(stock, report_dates)
        date = report_dates.select { |d| d > Date.current }.max
        return false unless date

        DataQualityIssue.record!(
          stock, "financial", "future_report_date",
          severity: "error",
          detail: { report_date: date.to_s, today: Date.current.to_s }
        )
        true
      end

      # { "income_statement" => Set<Date>, ... }
      def child_report_dates(stock)
        CHILD_MODELS.transform_values do |model|
          model.where(stock_id: stock.id).distinct.pluck(:report_date).compact.to_set
        end
      end
    end
  end
end
