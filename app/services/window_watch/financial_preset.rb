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
      # market（契约 v0.8）：CN=固定 12-31 年报口径；US=最近 N 份年报口径（见 us_preset_metrics）
      def preset_metrics(years:, mode:, band:, market: "CN")
        return us_preset_metrics(years, mode, band) if market == "US"

        dates = fiscal_years(count: years).map { |y| Date.new(y, 12, 31) }
        Rails.cache.fetch(["ww_fin_preset", market, years, mode, band, dates.first], expires_in: 24.hours) do
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

      # US 口径（契约 v0.8 承载，2026-11-26 定）：美股财年截止日分散（AAPL 九月/NVDA 一月等），
      # 不能复用 CN 固定 12-31 过滤——改「每只最近 N 份年报」+「最新年报距今 ≤15 个月」新鲜度闸，三维判定式同 CN
      def us_preset_metrics(years, mode, band)
        Rails.cache.fetch(["ww_fin_preset_us", years, mode, band], expires_in: 24.hours) do
          roes = FinancialIndicator.where(market: "US", period_type: "annual").where.not(roe_avg: nil)
                                   .order(:stock_id, report_date: :desc)
                                   .pluck(:stock_id, :report_date, :roe_avg)
                                 .group_by(&:first)
          ocf = CashFlow.where(market: "US", period_type: "annual")
                        .pluck(:stock_id, :report_date, :operating_cash_flow)
                        .each_with_object({}) { |(sid, d, v), h| h[[sid, d]] = v.to_f }
          symbols = Stock.where(id: roes.keys).pluck(:id, :symbol).to_h
          cutoff = Date.current - 15.months

          roes.each_with_object({}) do |(sid, list), out|
            recent = list.first(years)
            next if recent.size < years # 年报不足 N 份（上市短/披露缺失）自然不命中
            next if recent.first[1] < cutoff # 最新年报过旧，视同数据不可信
            next unless recent.all? { |(_, d, _)| ocf[[sid, d]].to_f.positive? } # 每年经营现金流为正（同 CN）
            vals = recent.map { |(_, _, v)| v.to_f }
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

      # 逐行标注 overlay：symbol => { name:, industry:, sector:, pyramid:, finance:, st:, roe_latest:, stock: }
      # 一次批量查询渲染页内全部行；财务库未覆盖的行返回技术判定所需最小信息（join 兜底，常态非异常）
      # 注：预设视图 ROE 列取 preset_metrics 主值；roe_latest 仅供全量视图 ROE 列
      # stock=站内 Stock 对象（同请求视图层消费：收藏组件/详情页链接），避免行渲染再查一次
      def overlay(rows, market: "CN")
        symbols = rows.map { |r| r.code.to_s.upcase }
        # market（契约 v0.8）：US 行 code=裸 Yahoo 码=站内 symbol 同值，按 market 限定防跨市场误命中
        stocks = Stock.where(market: market, symbol: symbols).index_by(&:symbol)
        roe_map = latest_annual_roe(stocks.values.map(&:id), market: market)
        stocks.transform_values do |s|
          {
            name: s.name, industry: s.industry.to_s, sector: s.sector.to_s,
            pyramid: s.pyramid_total_score,
            finance: financial_stock?(s), st: st_flag?(s),
            roe_latest: roe_map[s.id], stock: s
          }
        end
      end

      # 金融行业口径沿用库内现成正则（unlevered_roe_service）：sector=银行 或 industry 含银行/证券/保险
      def financial_stock?(stock)
        stock.sector.to_s == "银行" || stock.industry.to_s.match?(/银行|证券|保险/)
      end

      # ST 标注仅 CN 有意义：美股英文名（Sterling…）会撞 ST 前缀正则，v0.8 防误标
      def st_flag?(stock)
        stock.market.to_s == "CN" && stock.name.to_s.match?(/\A\*?ST/)
      end

      # 每只股票仅取最新一期年报 ROE：PostgreSQL DISTINCT ON 单查询（评审修复3；v0.8 market 参数化）
      def latest_annual_roe(stock_ids, market: "CN")
        return {} if stock_ids.empty?
        sql = "SELECT DISTINCT ON (stock_id) stock_id, roe_avg FROM financial_indicators " \
              "WHERE period_type = 'annual' AND market = :market AND roe_avg IS NOT NULL " \
              "AND stock_id IN (:ids) ORDER BY stock_id, report_date DESC"
        FinancialIndicator.find_by_sql([sql, { ids: stock_ids, market: market }])
                        .each_with_object({}) { |r, h| h[r.stock_id] = r.roe_avg }
      end
    end
  end
end
