module DataSources
  # 数据质量体检：把「看起来没报错但实际不对」的数据挑出来，落 DataQualityIssue 台账
  #
  # 覆盖两类数据：
  #   - 月K：缺月、后复权因子下降（应只增不改）、前后复权常数关系偏离
  #   - 财务：同一报告期只入库了部分子表（剔除数据源覆盖边界与披露时滞）、关键字段全空、报告日在未来
  # 「数值溢出被置空」不在这里扫描，由 BaseFetcher 写入时实时上报。
  class DataQualityService
    # 财务四张子表：完整的一期财务数据应四表齐全
    CHILD_MODELS = {
      "income_statement" => IncomeStatement,
      "balance_sheet" => BalanceSheet,
      "cash_flow" => CashFlow,
      "financial_indicator" => FinancialIndicator
    }.freeze

    # 披露时滞：报告日距今不足天数的期次跳过完整性检查。
    # 财报季数据源常已列出期次但部分子表尚未披露；取 A股年报最晚截止（120 天）之上再留余量
    DISCLOSURE_GRACE_DAYS = 150
    # 检查窗口：只核对近 N 年（≈近 16 期季报 + 近 4 期年报）的期次完整性。
    # 窗口外的历史期次数据源存在散点缺失（小盘股/SPAC 招股期次等），重抓也无法补齐，不做判定
    CHECK_WINDOW_YEARS = 4

    # 月K扫描的问题类型（用于复检通过后自动关闭不再复现的记录）
    MONTHLY_ISSUE_TYPES = %w[month_gap hfq_factor_decrease ratio_deviation].freeze
    # 财务扫描的问题类型（value_overflow 由 BaseFetcher 实时上报，不在扫描判定范围）
    FINANCIAL_ISSUE_TYPES = %w[partial_period empty_financials future_report_date].freeze

    # 因子下降容差：库内后复权因子为逐月递推乘积后按 scale 10 舍入存储，
    # 递推舍入噪声实测落在相对降幅 1e-6~1e-5 量级（2026-10-05 扫描 475 条全部在此区间、无一超 1e-4）；
    # 真实除权口径写坏至少百分之几量级，故取 1e-5——仍低于真实异常 3 个数量级，不会漏报
    FACTOR_DECREASE_EPSILON = 1e-5
    # 缺月只报近 N 个月内结束的：历史缺月绝大多数是整月停牌（库内无日线无法离线判别），重抓补不齐
    MONTH_GAP_RECENT_MONTHS = 12
    # 价格半分钱误差（存储列实为 decimal(12,4)，但行情展示口径 2 位），用于估算复权比值的舍入噪声。
    # 作为噪声上界偏保守（高估噪声 → 少误报），与 record_ratio_deviation 的容差模型配套
    PRICE_ROUNDING = BigDecimal("0.005")

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
        found = []
        bars = stock.stock_monthly_bars.chronological.pluck(:trade_date, :hfq_factor, :hfq_close, :qfq_close)
        if bars.size >= 2
          found << "month_gap" if record_month_gap(stock, bars)
          found << "hfq_factor_decrease" if record_factor_decrease(stock, bars)
          found << "ratio_deviation" if record_ratio_deviation(stock, bars)
        end
        auto_resolve_stale(stock, "monthly_bar", found, MONTHLY_ISSUE_TYPES)
        found.size
      end

      # ── 财务 ──
      def check_financials(stock)
        report_dates = stock.financial_reports.pluck(:report_date).compact.uniq
        return 0 if report_dates.empty?

        found = []
        found << "partial_period" if record_partial_period(stock, report_dates)
        found << "empty_financials" if record_empty_financials(stock, report_dates)
        found << "future_report_date" if record_future_report_date(stock, report_dates)
        auto_resolve_stale(stock, "financial", found, FINANCIAL_ISSUE_TYPES)
        found.size
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

      # 复检通过：自动关闭该股票此数据类型下不再复现的未处理记录，
      # 使判定规则收紧后存量误报在下次扫描自然消化，台账不跨周期累积过时问题
      def auto_resolve_stale(stock, data_type, found_types, all_types)
        stale = all_types - found_types
        return if stale.empty?

        DataQualityIssue.open.where(stock_id: stock.id, data_type: data_type, issue_type: stale)
                         .update_all(resolved_at: Time.current, resolution: "auto_resolved")
      end

      # 相邻两个月K行之间月份差 > 1。历史缺月多为整月停牌（重抓补不齐、无法离线判别），
      # 只报缺月结束于近 MONTH_GAP_RECENT_MONTHS 个月内的，detail 记区间供人工复核
      def record_month_gap(stock, bars)
        recent_start = (Date.current - MONTH_GAP_RECENT_MONTHS.months).beginning_of_month
        bars.each_cons(2) do |(prev_date, *), (date, *)|
          gap = (date.year * 12 + date.month) - (prev_date.year * 12 + prev_date.month)
          next if gap <= 1 || date < recent_start

          DataQualityIssue.record!(
            stock, "monthly_bar", "month_gap",
            severity: "warning",
            detail: { from: prev_date.to_s, to: date.to_s, missing_months: gap - 1 }
          )
          return true
        end
        false
      end

      # 后复权因子只增不改：相对降幅超过 FACTOR_DECREASE_EPSILON 才算口径被写坏，
      # 以内为递推乘积的定点舍入噪声（2026-10-05 实测 475 条残留全部落在 1e-6~1e-5 区间）
      def record_factor_decrease(stock, bars)
        bars.each_cons(2) do |(prev_date, prev_factor, *), (date, factor, *)|
          next if prev_factor.nil? || factor.nil?

          prev = prev_factor.to_d
          next if prev.zero?

          rel_decrease = (factor.to_d - prev) / prev
          next if rel_decrease >= -FACTOR_DECREASE_EPSILON

          DataQualityIssue.record!(
            stock, "monthly_bar", "hfq_factor_decrease",
            severity: "error",
            detail: {
              from: prev_date.to_s, to: date.to_s,
              prev_factor: prev_factor.to_s, factor: factor.to_s,
              relative_decrease: rel_decrease.to_f
            }
          )
          return true
        end
        false
      end

      # 同一只股票任意两行的 后复权收盘 ÷ 前复权收盘 必须是同一常数。
      # 收盘价定点存储存在舍入误差，比值的相对噪声 ≈ 2×(0.005/后复权价 + 0.005/前复权价)，
      # 低价股可达 0.5% 量级；基准行（首行＝上市初期，最易极低价）自身也有噪声，
      # 偏差需同时超过基础容差与「偏差行噪声 + 基准行噪声」才报（存量 1953 条中 1704 条 <0.1%）
      def record_ratio_deviation(stock, bars)
        ratios = bars.filter_map do |(date, _factor, hfq_close, qfq_close)|
          hfq = hfq_close.to_d
          qfq = qfq_close.to_d
          next if hfq_close.blank? || qfq.zero? || hfq.zero?

          noise = 2 * (PRICE_ROUNDING / hfq + PRICE_ROUNDING / qfq)
          [ date, hfq / qfq, noise ]
        end
        return false if ratios.size < 2

        expected, expected_noise = ratios.first[1], ratios.first[2]
        date, ratio, noise = ratios.max_by { |(_d, r, _n)| ((r - expected) / expected).abs }
        deviation = ((ratio - expected) / expected).abs
        tolerance = [ SinaMonthlyBarService::RATIO_TOLERANCE, noise + expected_noise ].max
        return false if deviation <= tolerance

        DataQualityIssue.record!(
          stock, "monthly_bar", "ratio_deviation",
          severity: "error",
          detail: { sample_date: date.to_s, expected_ratio: expected.to_s, actual_ratio: ratio.to_s,
                    max_deviation: deviation.to_f, tolerance: tolerance.to_f }
        )
        true
      end

      # 同一报告期只入库了部分子表
      #
      # 三类「不齐全」不算抓取错误，予以剔除：
      #   - 历史覆盖边界：各子表在数据源中的历史起点不同（如 A股现金流量表 1996 年才有披露要求、
      #     东财美股/港股资产负债表深度有限），只检查「有数据的子表」共同起点之后的期次；
      #     整只股票都没有数据的子表视为数据源不覆盖，不参与判定
      #   - 披露时滞：报告日距今不足 DISCLOSURE_GRACE_DAYS 的期次跳过（财报季部分子表尚未披露）
      #   - 窗口外历史散点缺失：只检查近 CHECK_WINDOW_YEARS 年的期次
      def record_partial_period(stock, report_dates)
        present = child_report_dates(stock)
        covered = present.reject { |_name, dates| dates.empty? }
        return false if covered.size < 2

        coverage_start = covered.values.map(&:min).max
        window_start = Date.current - CHECK_WINDOW_YEARS.years
        deadline = Date.current - DISCLOSURE_GRACE_DAYS
        checkable = report_dates.select do |d|
          d >= coverage_start && d >= window_start && d <= deadline
        end

        checkable.sort.reverse_each do |date|
          tables = covered.keys.select { |name| covered[name].include?(date) }
          next if tables.size.zero? || tables.size == covered.size

          DataQualityIssue.record!(
            stock, "financial", "partial_period",
            severity: "warning",
            detail: { report_date: date.to_s, present_tables: tables,
                      missing_tables: covered.keys - tables }
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
