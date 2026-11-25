module WindowWatch
  # 页面侧财务预设（契约 v0.4.0 §三.1 / 需求单 v0.3.0 移交）：
  # 命中规则 = 近 3 个完整财年每年 ROE≥档位% 且 每年经营活动现金流净额>0（最新披露口径）
  # 数据源 = Trae 财务库（financial_indicators.roe_avg / cash_flows.operating_cash_flow，annual 期次）
  # 注意：展示口径为「最新披露」，与 DSH 回测链 as-of 判定月口径语义不同，两者不得对账
  class FinancialPreset
    BANDS = [10, 15, 20].freeze
    DEFAULT_BAND = 15

    class << self
      def band_for(param)
        v = param.to_s.to_i
        BANDS.include?(v) ? v : DEFAULT_BAND
      end

      # 近 3 个完整财年（去年年报起算；未披露年报的年份自然无行、不命中）
      def fiscal_years(now = Date.current)
        last = now.year - 1
        [last, last - 1, last - 2]
      end

      # 命中预设的站内 symbol 集合（如 "SH601985"）；按档位+日期缓存（财报日批更新后自然刷新）
      def hit_symbols(band:)
        years = fiscal_years
        Rails.cache.fetch(["ww_fin_preset", band, years.first], expires_in: 24.hours) do
          roe_ids = FinancialIndicator.where(market: "CN", period_type: "annual")
            .where(report_date: years.map { |y| Date.new(y, 12, 31) })
            .where("roe_avg >= ?", band)
            .group(:stock_id).having("COUNT(DISTINCT report_date) = 3").pluck(:stock_id)
          ocf_ids = CashFlow.where(market: "CN", period_type: "annual")
            .where(report_date: years.map { |y| Date.new(y, 12, 31) })
            .where("operating_cash_flow > 0")
            .group(:stock_id).having("COUNT(DISTINCT report_date) = 3").pluck(:stock_id)
          Stock.where(id: roe_ids & ocf_ids).pluck(:symbol).to_set
        end
      end

      # 逐行财务标注 overlay：symbol => { name:, industry:, finance:, st:, roe_latest: }
      # 一次批量查询渲染页内全部行；财务库未覆盖的行返回技术判定所需最小信息（join 兜底，常态非异常）
      def overlay(rows)
        symbols = rows.map { |r| r.code.to_s.upcase }
        stocks = Stock.where(symbol: symbols).index_by(&:symbol)
        roe_map = latest_annual_roe(stocks.values.map(&:id))
        stocks.transform_values do |s|
          {
            name: s.name, industry: s.industry.to_s,
            finance: financial_stock?(s), st: s.name.to_s.match?(/\A\*?ST/),
            roe_latest: roe_map[s.id]
          }
        end
      end

      # 金融行业口径沿用库内现成正则（unlevered_roe_service）：sector=银行 或 industry 含银行/证券/保险
      def financial_stock?(stock)
        stock.sector.to_s == "银行" || stock.industry.to_s.match?(/银行|证券|保险/)
      end

      # 每只股票仅取最新一期年报 ROE：PostgreSQL DISTINCT ON 单查询（评审修复3）
      def latest_annual_roe(stock_ids)
        return {} if stock_ids.empty?
        sql = "SELECT DISTINCT ON (stock_id) stock_id, roe_avg FROM financial_indicators " \
              "WHERE period_type = 'annual' AND market = 'CN' AND roe_avg IS NOT NULL " \
              "AND stock_id IN (:ids) ORDER BY stock_id, report_date DESC"
        FinancialIndicator.find_by_sql([sql, { ids: stock_ids }])
                        .each_with_object({}) { |r, h| h[r.stock_id] = r.roe_avg }
      end
    end
  end
end
