module WindowWatch
  # 页面侧财务预设（契约 v0.4.0 §三.1 / 需求单 v0.3.0 移交；2026-11-25 老板定三维筛选）：
  # 命中规则 = 近 N（3/5）个完整财年 ROE 按所选方式满足阈值（10/15/20%）且每年经营活动现金流净额>0（最新披露口径）
  #   连续满足：每年 ROE ≥ 阈值；主值 = N 年最小值
  #   平均满足：N 年算术平均 ≥ 阈值 且 每年 ROE ≥ 阈值×70%；主值 = N 年算术平均
  # 主值即卡片「ROE(筛选值)」列的展示数（不再取最新单年）
  # 注意：展示口径为「最新披露」，与 DSH 回测链 as-of 判定月口径语义不同，两者不得对账
  class FinancialPreset
    BANDS = [10, 15, 20].freeze
    # R1（2026-11-25 老板定）：默认档位 15%→10%
    DEFAULT_BAND = 10
    YEARS = [3, 5].freeze
    DEFAULT_YEARS = 3
    MODES = %w[consecutive average].freeze
    DEFAULT_MODE = "consecutive"
    MODE_NAMES = { "consecutive" => "连续满足", "average" => "平均满足" }.freeze
    # 平均满足的逐年下限 = 阈值 × 70%（2026-11-25 老板定）
    AVG_FLOOR_RATIO = 0.7

    class << self
      def band_for(param)
        v = param.to_s.to_i
        BANDS.include?(v) ? v : DEFAULT_BAND
      end

      def years_for(param)
        v = param.to_s.to_i
        YEARS.include?(v) ? v : DEFAULT_YEARS
      end

      def mode_for(param)
        v = param.to_s
        MODES.include?(v) ? v : DEFAULT_MODE
      end

      # 近 count 个完整财年（去年年报起算；未披露年报的年份自然无行、不命中）
      def fiscal_years(now = Date.current, count: DEFAULT_YEARS)
        last = now.year - 1
        (0...count).map { |i| last - i }
      end

      # 命中集与筛选主值：{ 站内 symbol（如 "SH601985"）=> 主值 Float }
      # 主值：连续满足=N 年 ROE 最小值；平均满足=N 年算术平均。按三维组合+年度键缓存（财报日批更新后自然刷新）
      def preset_metrics(years:, mode:, band:)
        dates = fiscal_years(count: years).map { |y| Date.new(y, 12, 31) }
        Rails.cache.fetch(["ww_fin_preset", years, mode, band, dates.first], expires_in: 24.hours) do
          roe_by_stock = FinancialIndicator.where(market: "CN", period_type: "annual")
                                           .where(report_date: dates).where.not(roe_avg: nil)
                                           .pluck(:stock_id, :report_date, :roe_avg)
                                           .each_with_object({}) { |(sid, d, v), h| (h[sid] ||= {})[d] = v.to_f }
          # 现金流门槛两种模式一致：每年经营现金流净额>0（2026-11-25 老板定）
          ocf_ok = CashFlow.where(market: "CN", period_type: "annual")
                           .where(report_date: dates)
                           .where("operating_cash_flow > 0")
                           .group(:stock_id).having("COUNT(DISTINCT report_date) = #{dates.size}")
                           .pluck(:stock_id).to_set
          symbols = Stock.where(id: roe_by_stock.keys).pluck(:id, :symbol).to_h

          roe_by_stock.each_with_object({}) do |(sid, by_date), out|
            next unless ocf_ok.include?(sid)
            vals = dates.sort.map { |d| by_date[d] }
            next if vals.any?(&:nil?) # 要求每年均有年报 ROE（上市不足 N 年自然不命中）
            metric = if mode == "average"
                       mean = vals.sum / vals.size
                       mean if mean >= band && vals.min >= band * AVG_FLOOR_RATIO
                     else
                       vals.min if vals.all? { |v| v >= band }
                     end
            sym = symbols[sid]
            out[sym] = metric.round(2) if metric && sym
          end
        end
      end

      # 逐行标注 overlay：symbol => { name:, industry:, sector:, pyramid:, finance:, st:, roe_latest: }
      # 一次批量查询渲染页内全部行；财务库未覆盖的行返回技术判定所需最小信息（join 兜底，常态非异常）
      # 注：预设视图 ROE 列取 preset_metrics 主值；roe_latest 仅供全量表格视图徽章
      def overlay(rows)
        symbols = rows.map { |r| r.code.to_s.upcase }
        stocks = Stock.where(symbol: symbols).index_by(&:symbol)
        roe_map = latest_annual_roe(stocks.values.map(&:id))
        stocks.transform_values do |s|
          {
            name: s.name, industry: s.industry.to_s, sector: s.sector.to_s,
            pyramid: s.pyramid_total_score,
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
