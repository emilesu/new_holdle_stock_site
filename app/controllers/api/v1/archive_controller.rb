module Api
  module V1
    # 企业质量档案只读数据接口（契约见 .trae/documents/企业质量档案接口对齐方案_20261012.md）
    # 供档案生成侧 build_facts_v2.py 取数：
    #   GET /api/v1/archive/pyramid?code=603259.SH      金字塔总分 + 同业 TopN
    #   GET /api/v1/archive/financials?code=603259.SH&period=2025  财报字段（归母口径 + 扣非 + 披露日期）
    # 服务间 Bearer token 鉴权（HOLDLE_ARCHIVE_TOKEN），不对外、无登录态
    # 数值契约：金额/比率字段为 BigDecimal，JSON 序列化为字符串以保留分到位的精度（如 "45456165774.18"），
    #           消费侧应用 Decimal 解析而非 float；rank/score 等为整数原样输出
    class ArchiveController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :verify_service_token

      PEERS_LIMIT = 10
      DEFAULT_HISTORY_YEARS = 10
      RANKING_DEFAULT_LIMIT = 100
      RANKING_MAX_LIMIT = 1000
      # 字段缺失时的统一 caliber 标注：绝不回退成含少数股东口径
      PENDING_CALIBER = "源未提供/待回填".freeze

      # 接口1：金字塔总分 + 同业 peers（申万一级/二级两份 Top10）
      def pyramid
        stock = find_stock
        return render_not_found unless stock

        render json: { success: true, data: pyramid_payload(stock) }
      end

      # 接口2：财报字段。period 支持 "2025"/"2025年报"，缺省取最新年报期；history 缺省 10
      def financials
        stock = find_stock
        return render_not_found unless stock

        indicator = annual_indicator_for(stock, params[:period])
        unless indicator
          return render json: { success: false, error: "无该期次年报数据" }, status: 404
        end

        render json: { success: true, data: financials_payload(stock, indicator) }
      end

      # 接口3：金字塔榜单（契约见 23_Trae榜单接口需求_20261013.md）
      # 口径与站内 /pyramid 页逐位一致：pyramid_total_score DESC, id DESC（id 为主键，天然稳定 tie-break，分页不重不漏）
      # 排除未计算标的：pyramid_total_score 为 default 0 NOT NULL，「已计算」的唯一标记是 last_pyramid_calc_at 非空
      # 本期仅 market=cn（A股，含北交所）；港美股未纳入
      def ranking
        # 参数一律先 to_s 再转换：数组型畸形参数（?limit[]=1）to_s 后走默认值/400 路径，避免 NoMethodError→500
        market = params[:market].to_s.presence || "cn"
        unless market.casecmp?("cn")
          return render json: { success: false, error: "本期仅支持 market=cn（A股，含北交所）" }, status: 400
        end

        raw_limit = (params[:limit].to_s.presence || RANKING_DEFAULT_LIMIT).to_i
        raw_limit = 1 if raw_limit < 1
        capped = raw_limit > RANKING_MAX_LIMIT
        limit = [raw_limit, RANKING_MAX_LIMIT].min
        offset = [params[:offset].to_s.to_i, 0].max

        scope = Stock.where(market: "CN").where.not(last_pyramid_calc_at: nil)
        min_score = params[:min_score].to_s.presence
        scope = scope.where("pyramid_total_score >= ?", min_score.to_i) if min_score

        total = scope.count
        stocks = scope.order(pyramid_total_score: :desc, id: :desc).offset(offset).limit(limit).to_a
        periods = batch_data_period(stocks.map(&:id))

        items = stocks.each_with_index.map do |stock, idx|
          {
            rank: offset + idx + 1,
            code: display_code(stock),
            name: stock.name,
            market: stock.market,
            board: derive_board(stock),
            sw_l1: stock.sector,
            sw_l2: stock.industry,
            pyramid_score: stock.pyramid_total_score.to_i,
            data_period: periods[stock.id],
            last_calc_at: stock.last_pyramid_calc_at.in_time_zone.iso8601
          }
        end

        data = {
          total: total,
          snapshot_at: scope.maximum(:last_pyramid_calc_at)&.in_time_zone&.iso8601,
          items: items
        }
        data[:warning] = "limit 超过上限，已按 #{RANKING_MAX_LIMIT} 截断" if capped

        render json: { success: true, data: data }
      end

      private

      def verify_service_token
        expected = ENV["HOLDLE_ARCHIVE_TOKEN"].to_s
        token = request.headers["Authorization"].to_s.remove("Bearer ")
        return if expected.present? && token == expected

        render json: { success: false, error: "unauthorized" }, status: 401
      end

      def render_not_found
        render json: { success: false, error: "stock not found" }, status: 404
      end

      # code 归一化：支持 603259.SH 后缀式（库内为 SH603259 前缀式）与原始 symbol，
      # 前缀式大小写不敏感（sh603259 → SH603259）
      def find_stock
        raw = params[:code].to_s.strip
        return nil if raw.empty?

        if (m = raw.match(/\A(\d{6})\.(SH|SZ|BJ)\z/i))
          stock = Stock.find_by(symbol: "#{m[2].upcase}#{m[1]}")
        elsif (m = raw.match(/\A(SH|SZ|BJ)(\d{6})\z/i))
          stock = Stock.find_by(symbol: "#{m[1].upcase}#{m[2]}")
        end
        stock || Stock.find_by(symbol: raw)
      end

      # 输出统一后缀式：SZ000001 → 000001.SZ；港/美等原样返回
      def display_code(stock)
        if (m = stock.symbol.to_s.match(/\A(SH|SZ|BJ)(\d+)\z/))
          "#{m[2]}.#{m[1]}"
        else
          stock.symbol
        end
      end

      # 板块推导（仅 A 股）：688 科创板 / 30 创业板 / BJ 北交所 / 其余主板
      def derive_board(stock)
        return nil unless stock.market == "CN"
        return "北交所" if stock.symbol.to_s.start_with?("BJ")

        code = stock.symbol.to_s[/\d+/]
        return nil if code.nil?

        case code
        when /\A688/ then "科创板"
        when /\A30/ then "创业板"
        else "主板"
        end
      end

      def pyramid_payload(stock)
        {
          code: display_code(stock),
          name: stock.name,
          market: stock.market,
          sw_l1: stock.sector,
          sw_l2: stock.industry,
          board: derive_board(stock),
          pyramid_score: stock.pyramid_total_score.to_i,
          data_period: pyramid_data_period(stock),
          last_calc_at: stock.last_pyramid_calc_at&.in_time_zone&.iso8601,
          peers: peers_payload(stock)
        }
      end

      # 评分所用财报期：与 StockPyramidService 同口径（近5年窗口内最新年报）
      def pyramid_data_period(stock)
        years = stock.financial_years.select { |y| y.to_i >= Date.current.year - 5 }.sort
        years.empty? ? nil : "#{years.last}年报"
      end

      # 批量版 pyramid_data_period（榜单专用，避免逐只 financial_years 的 N+1）：
      # 窗口内 MAX(report_date) 与单只口径逐值等价（financial_years 取近20年，窗口仅近5年，MAX 必落在其中）
      def batch_data_period(stock_ids)
        return {} if stock_ids.empty?

        min_date = Date.new(Date.current.year - 5, 1, 1)
        FinancialIndicator.where(stock_id: stock_ids, period_type: "annual")
                          .where(report_date: min_date..)
                          .group(:stock_id).maximum(:report_date)
                          .transform_values { |d| "#{d.year}年报" }
      end

      def peers_payload(stock)
        {
          sw_l1_top: peers_for(stock, :sector),
          sw_l2_top: peers_for(stock, :industry),
          rank_in_sw_l2: rank_within(stock, :industry)
        }
      end

      # 同业 TopN：排序口径与 /pyramid 页完全一致（score desc, id desc），命中现成索引
      def peers_for(stock, column)
        value = stock.public_send(column)
        return [] if value.blank?

        Stock.where(market: stock.market, column => value)
             .order(pyramid_total_score: :desc, id: :desc)
             .limit(PEERS_LIMIT)
             .each_with_index.map do |peer, idx|
          {
            rank: idx + 1,
            code: display_code(peer),
            name: peer.name,
            pyramid_score: peer.pyramid_total_score.to_i
          }
        end
      end

      # 标的在二级行业内的名次（与 peers 同排序键：分数高者在前，同分 id 大者在前）
      def rank_within(stock, column)
        value = stock.public_send(column)
        return nil if value.blank?

        scope = Stock.where(market: stock.market, column => value)
        higher = scope.where("pyramid_total_score > ?", stock.pyramid_total_score).count
        same = scope.where(pyramid_total_score: stock.pyramid_total_score).where("id > ?", stock.id).count
        higher + same + 1
      end

      def annual_indicator_for(stock, period)
        scope = stock.financial_indicators.where(period_type: "annual").where.not(report_date: nil)
        year = period.to_s[/\d{4}/]
        if year
          scope.where(report_date: Date.new(year.to_i, 1, 1)..Date.new(year.to_i, 12, 31))
               .order(report_date: :desc).first
        else
          scope.order(report_date: :desc).first
        end
      end

      def financials_payload(stock, indicator)
        report_date = indicator.report_date
        income = stock.income_statements.find_by(report_date: report_date, market: stock.market)
        balance = stock.balance_sheets.find_by(report_date: report_date, market: stock.market)
        cash = stock.cash_flows.find_by(report_date: report_date, market: stock.market)

        revenue = income&.total_revenue
        parent = income&.net_income_to_shareholders
        deducted = indicator.deducted_net_profit
        cash_val = balance&.cash_and_cash_equivalents
        total_assets = balance&.total_assets

        {
          code: display_code(stock),
          period: stock.period_label("annual", report_date),
          report_date: report_date.to_s,
          disclosed_at: indicator.disclosed_at&.to_s,
          fields: {
            revenue: field(revenue, "合并·营业总收入", "eastmoney"),
            parent_net_profit: field(parent, "归属于上市公司股东的净利润", "eastmoney"),
            parent_net_margin: field(ratio(parent, revenue), "归母净利÷营业总收入", "derived"),
            deducted_net_profit: field(deducted, "扣非归母净利润", "eastmoney_f10"),
            non_recurring_net: field(subtract(parent, deducted), "归母净利−扣非归母净利", "derived"),
            roe_weighted: field(indicator.roe_avg, "加权平均ROE·归母(WEIGHTAVG_ROE)", "eastmoney"),
            deducted_roe_weighted: field(indicator.deducted_roe_weighted, "扣非加权平均ROE", "eastmoney_f10"),
            cash_and_equivalents: field(cash_val, "货币资金", "eastmoney"),
            total_assets: field(total_assets, "合并总资产", "eastmoney"),
            cash_ratio: field(ratio(cash_val, total_assets), "货币资金÷总资产", "derived"),
            op_cashflow: field(cash&.operating_cash_flow, "经营活动产生的现金流量净额", "eastmoney"),
            eps_basic: field(indicator.basic_eps, "基本每股收益", "eastmoney"),
            eps_diluted: field(indicator.eps_diluted, "稀释每股收益(EPSXS)", "eastmoney_f10"),
            eps_deducted: field(indicator.diluted_eps, "扣非基本每股收益(DEDUCT_BASIC_EPS)", "eastmoney")
          },
          history: history_payload(stock)
        }
      end

      # 统一 {value, caliber, source} 结构；value 为 nil 时 caliber 标注缺失原因
      def field(value, caliber, source)
        if value.nil?
          { value: nil, caliber: PENDING_CALIBER, source: nil }
        else
          { value: value, caliber: caliber, source: source }
        end
      end

      # 派生比率：未舍入原值现算，2 位小数；分母缺失或为 0 返回 nil
      def ratio(numerator, denominator)
        return nil unless numerator && denominator && denominator != 0

        (numerator / denominator * 100).round(2)
      end

      # 派生差值：任一操作数缺失返回 nil
      def subtract(a, b)
        return nil unless a && b

        (a - b).round(2)
      end

      # 近 N 个年报期序列：ROE/毛利率为报表口径，净利率为归母口径（net_sales_rate），负债率同源
      def history_payload(stock)
        years = (params[:history].presence || DEFAULT_HISTORY_YEARS).to_i.clamp(1, 20)
        stock.financial_indicators
             .where(period_type: "annual").where.not(report_date: nil)
             .order(report_date: :desc).limit(years)
             .map do |ind|
          {
            period: stock.period_label("annual", ind.report_date),
            roe_weighted: ind.roe_avg,
            gross_margin: ind.gross_margin,
            parent_net_margin: ind.net_sales_rate,
            asset_liab_ratio: ind.asset_liab_ratio
          }
        end
      end
    end
  end
end
