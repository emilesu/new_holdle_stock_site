module DataSources
  # Yahoo 美股财务指标回退服务
  #
  # 背景：东财指标接口（RPT_USF10_FN_GMAININDICATOR / RPT_USF10_FN_IMAININDICATOR）
  #   对部分美股（实测 SOFI 及同类约 800 只）直接返回空，导致 financial_indicators 零行，
  #   股票详情页财务列全空、金字塔分算不出。雪球源历史验证不可用，故改用 Yahoo。
  #
  # 数据流：Yahoo fundamentals-timeseries（免鉴权，与月K同域名同 Faraday 封装）
  #   → 原始年度科目（EPS/营收/净利/毛利/总资产/总负债/股东权益/流动资产负债/存货）
  #   → 按东财口径推导比率 → 按「同年同月」对齐站内已存在的 annual 期次 → 交由 UsFetcher 落库
  #
  # 口径对齐（2026-10-13 用 AAPL 与库内东财值逐位实测）：
  #   gross_margin = 毛利 ÷ 营收 × 100        → 46.91 ≡ 46.91
  #   net_sales_rate = 归母净利 ÷ 营收 × 100   → 26.92 ≡ 26.92
  #   roe_avg = 归母净利 ÷ 平均权益 × 100      → 171.4 ≡ 171.42（平均权益 =（期初+期末）÷2）
  #   net_interest_of_ta = 归母净利 ÷ 平均资产 × 100 → 30.93 ≡ 30.93
  #   current_ratio = 流动资产 ÷ 流动负债       → 0.893 ≡ 0.89
  #   quick_ratio =（流动资产 − 存货）÷ 流动负债 → 0.858 ≡ 0.86
  #   asset_liab_ratio = 总负债 ÷ 总资产 × 100   → 79.48 ≡ 79.48
  #   平均口径需上一期权益/资产；最早一期无前值时退化为期末单点（与东财略有偏差，可接受）。
  #
  # 仅补年报（period_type='annual'）：东财季报指标为累计口径，Yahoo 季报为单季口径，
  #   跨财年累加易错且资产负债类科目不可累加，故季报不回退；年报足以支撑详情页年报列与金字塔（仅读 annual）。
  #
  # 历史深度：Yahoo 滚动仅返回近 4 个财年（实测 AAPL/SOFI 均 4 期），早年历史无法补齐。
  class YahooIndicatorService
    TS_BASE_URL = "https://query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 20
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    # period1=0 → Yahoo 钳制到 1970，取可得的最早年报
    PERIOD1_FULL = 0

    # 比率百分比换算的精度（对齐 financial_indicators numeric(20,2)）
    PERCENT_SCALE = 2
    RATIO_SCALE = 2

    # 一次请求带齐推导所需年度科目
    ANNUAL_FIELDS = %w[
      annualBasicEPS
      annualDilutedEPS
      annualTotalRevenue
      annualNetIncomeCommonStockholders
      annualNetIncome
      annualGrossProfit
      annualTotalAssets
      annualTotalLiabilitiesNetMinorityInterest
      annualStockholdersEquity
      annualCurrentAssets
      annualCurrentLiabilities
      annualInventory
    ].freeze

    class RequestError < StandardError; end

    class << self
      # HTTP 客户端，默认 Faraday，测试可替换
      attr_writer :http_client

      def http_client
        @http_client || Faraday
      end

      # 抓取单只美股的年度指标，返回按「同年同月」键的推导结果：
      #   { "2024-12" => { basic_eps:, diluted_eps:, gross_margin:, net_sales_rate:,
      #                    roe_avg:, net_interest_of_ta:, current_ratio:, quick_ratio:, asset_liab_ratio: }, ... }
      # 无数据/无法转换代码返回 {}。调用方（UsFetcher）负责与站内期次对齐并落库。
      def fetch_annual(stock)
        symbol = yahoo_symbol(stock)
        if symbol.nil?
          Rails.logger.warn "[YahooIndicator] #{stock.market}/#{stock.symbol} 无法转换为 Yahoo 代码，跳过"
          return {}
        end

        url = build_url(symbol)
        series = parse_series(request(url))
        build_indicators(series)
      rescue JSON::ParserError, RequestError, Faraday::Error => e
        Rails.logger.error "[YahooIndicator] #{stock.symbol} 指标抓取失败：#{e.message}"
        {}
      end

      # 库内 symbol → Yahoo 代码（与 YahooMonthlyBarService 同规则）：BRK.B → BRK-B
      def yahoo_symbol(stock)
        return nil unless stock.market == "US"

        symbol = stock.symbol.to_s.strip
        return nil if symbol.empty?

        symbol.upcase.tr("./", "--")
      end

      def build_url(symbol)
        types = ANNUAL_FIELDS.join(",")
        "#{TS_BASE_URL}/#{symbol}?symbol=#{CGI.escape(symbol)}&type=#{types}&period1=#{PERIOD1_FULL}&period2=#{Time.now.to_i}"
      end

      # 解析为 { field_name => { "YYYY-MM-DD" => BigDecimal } }
      def parse_series(body)
        result = JSON.parse(body).dig("timeseries", "result")
        return {} unless result.is_a?(Array)

        series = {}
        result.each do |block|
          next unless block.is_a?(Hash)

          field = block.dig("meta", "type", 0)
          rows = block[field]
          next if field.nil? || !rows.is_a?(Array)

          rows.each do |row|
            next unless row.is_a?(Hash)

            date = row["asOfDate"].to_s.split(" ").first
            raw = row.dig("reportedValue", "raw")
            next if date.empty? || raw.nil?

            value = to_decimal(raw)
            series[field] ||= {}
            series[field][date] = value if value
          end
        end
        series
      end

      # 按 asOfDate 汇总各科目，推导比率，键归一为「YYYY-MM」
      def build_indicators(series)
        dates = series.values.flat_map(&:keys).uniq.sort
        # 升序遍历，使平均口径能取到上一期（较早一期）权益/资产
        prev_equity = nil
        prev_assets = nil

        dates.filter_map do |date|
          equity = series.dig("annualStockholdersEquity", date)
          assets = series.dig("annualTotalAssets", date)
          # 归母净利优先（与东财「归属于母公司」口径一致），部分标的仅返回 annualNetIncome → 回退
          net_income = series.dig("annualNetIncomeCommonStockholders", date) ||
                       series.dig("annualNetIncome", date)
          revenue = series.dig("annualTotalRevenue", date)

          current_assets = series.dig("annualCurrentAssets", date)
          current_liabilities = series.dig("annualCurrentLiabilities", date)
          inventory = series.dig("annualInventory", date)
          quick_numerator = current_assets && inventory ? current_assets - inventory : current_assets

          data = {
            basic_eps: series.dig("annualBasicEPS", date),
            diluted_eps: series.dig("annualDilutedEPS", date),
            gross_margin: percent(series.dig("annualGrossProfit", date), revenue),
            net_sales_rate: percent(net_income, revenue),
            current_ratio: ratio(current_assets, current_liabilities),
            quick_ratio: ratio(quick_numerator, current_liabilities),
            # 口径限制：NetMinorityInterest 为扣少数股东后总负债，含少数股东权益的标的
            # 负债率较东财（含少数）偏低；AAPL 等无少数股东标的实测逐位一致（79.48 ≡ 79.48）
            asset_liab_ratio: percent(series.dig("annualTotalLiabilitiesNetMinorityInterest", date), assets)
          }

          # 平均权益/平均资产：有上一期取均值，否则退化期末单点
          avg_equity = equity && prev_equity ? (equity + prev_equity) / 2 : equity
          avg_assets = assets && prev_assets ? (assets + prev_assets) / 2 : assets
          data[:roe_avg] = percent(net_income, avg_equity)
          data[:net_interest_of_ta] = percent(net_income, avg_assets)

          prev_equity = equity if equity
          prev_assets = assets if assets

          compacted = data.compact
          next if compacted.empty?

          [date[0, 7], compacted]
        end.to_h
      end

      # 比率 = 分子 ÷ 分母 × 100，保留 2 位；分子/分母缺失或分母为 0 返回 nil
      def percent(numerator, denominator)
        return nil if numerator.nil? || denominator.nil? || denominator.zero?

        (numerator / denominator * 100).round(PERCENT_SCALE)
      end

      # 倍数比率 = 分子 ÷ 分母，保留 2 位
      def ratio(numerator, denominator)
        return nil if numerator.nil? || denominator.nil? || denominator.zero?

        (numerator / denominator).round(RATIO_SCALE)
      end

      def to_decimal(value)
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def request(url)
        retries = RETRY_TIMES
        begin
          response = http_client.get(url) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.options.timeout = TIMEOUT
            req.options.open_timeout = TIMEOUT
          end
          raise RequestError, "HTTP #{response.status}" unless response.success?

          response.body
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed, RequestError => e
          raise if retries.zero?

          retries -= 1
          Rails.logger.warn "[YahooIndicator] 请求异常，重试中（剩余 #{retries} 次）：#{e.message}"
          sleep RETRY_INTERVAL
          retry
        end
      end
    end
  end
end
