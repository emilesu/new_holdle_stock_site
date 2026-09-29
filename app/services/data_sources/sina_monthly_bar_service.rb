module DataSources
  # 新浪 A股月K抓取服务
  #
  # 数据流：不复权月K（scale=7200，一次取满全历史）+ 前/后复权因子 → 本地等比换算 → 落库 stock_monthly_bars
  #
  # 复权换算式（Task 0 探针已验证，见设计方案 §2.4.2）：
  #   后复权价 = 不复权价 × hfq_factor      （以上市首日归一，只增不改）
  #   前复权价 = 不复权价 ÷ qfq_factor      （以最新日归一，除权后整段重写）
  #
  # 重算策略（D9/D14）：
  #   :full        —— 全量重算并覆盖所有列（首次建库；前复权基准变更时使用）
  #   :incremental —— 已有历史行只更新前复权列，后复权列保持不动（后复权只增不改）
  class SinaMonthlyBarService
    KLINE_URL = "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData".freeze
    REFERER = "https://finance.sina.com.cn/".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 15
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    # 请求间隔（秒），避免触发数据源限流
    REQUEST_INTERVAL = 0.3

    # 7200 秒 = 2 小时周期 → 新浪月K
    SCALE = 7200
    # 实测单次可返回全历史（A股最长约 400 根月K）
    MAX_BARS = 1000

    PRICE_SCALE = 4
    FACTOR_SCALE = 10
    # 常数比值自检的相对误差容差
    RATIO_TOLERANCE = 1e-4

    # HTTP 非 2xx 响应（纳入重试范围）
    class RequestError < StandardError; end

    # 冲突时需要更新的列（created_at 不参与覆盖）
    FULL_UPDATE_COLUMNS = %i[
      market open close high low volume
      qfq_open qfq_close qfq_high qfq_low qfq_factor
      hfq_open hfq_close hfq_high hfq_low hfq_factor
      updated_at
    ].freeze

    # 增量模式：已有历史行只重写前复权列（前复权随时间整段变化），后复权列「只增不改」
    INCREMENTAL_UPDATE_COLUMNS = %i[qfq_open qfq_close qfq_high qfq_low qfq_factor updated_at].freeze

    class << self
      # HTTP客户端，默认为Faraday，测试时可替换
      attr_writer :http_client

      def http_client
        @http_client || Faraday
      end

      # 抓取单只股票并落库
      # 返回 { total:, inserted:, updated:, bars: }
      def refresh(stock, mode: :full)
        raw_bars = fetch_raw_bars(stock.symbol)
        if raw_bars.empty?
          Rails.logger.warn "[SinaMonthlyBar] #{stock.symbol} 未获取到月K数据"
          return empty_result
        end

        # 因子抓取失败时返回空数组；此时若继续换算，前/后复权价会双双退化为不复权价，
        # 且「后复权 ÷ 前复权」恒为 1 恰好通过 verify_constant_ratio 自检，属静默写错数据 ——
        # 故因子缺失直接跳过本只，不落库
        qfq_factors = SinaAdjFactorService.fetch_qfq(stock.symbol)
        hfq_factors = SinaAdjFactorService.fetch_hfq(stock.symbol)
        if qfq_factors.empty? || hfq_factors.empty?
          Rails.logger.error "[SinaMonthlyBar] #{stock.symbol} 复权因子缺失，跳过本只以避免写入未复权口径"
          return empty_result
        end

        bars = build_bars(stock, raw_bars, qfq_factors, hfq_factors)
        return empty_result if bars.empty?

        verify_constant_ratio(stock, bars)
        cleanup_stale_dates(stock, bars)

        before = stock.stock_monthly_bars.count
        update_columns = mode == :incremental ? INCREMENTAL_UPDATE_COLUMNS : FULL_UPDATE_COLUMNS
        stock.stock_monthly_bars.upsert_all(
          bars,
          unique_by: %i[stock_id trade_date],
          update_only: update_columns,
          record_timestamps: false
        )
        after = stock.stock_monthly_bars.count
        inserted = after - before

        { total: bars.size, inserted: inserted, updated: bars.size - inserted, bars: bars.size }
      end

      # 不复权月K全历史（新浪 getKLineData），按交易日升序
      def fetch_raw_bars(symbol)
        code = SinaAdjFactorService.sina_code(symbol)
        url = "#{KLINE_URL}?symbol=#{code}&scale=#{SCALE}&ma=no&datalen=#{MAX_BARS}"
        body = request(url)
        data = JSON.parse(body)
        return [] unless data.is_a?(Array)

        data.sort_by { |item| item["day"].to_s }
      rescue JSON::ParserError => e
        Rails.logger.error "[SinaMonthlyBar] #{code} 月K解析失败：#{e.message}"
        []
      end

      # 不复权月K + 两套因子 → 落库行数组
      def build_bars(stock, raw_bars, qfq_factors, hfq_factors, now: Time.current)
        qfq_cursor = [0]
        hfq_cursor = [0]

        raw_bars.filter_map do |raw|
          trade_date = parse_trade_date(raw["day"])
          open = to_decimal(raw["open"])
          close = to_decimal(raw["close"])
          next if trade_date.nil? || open.nil? || close.nil?

          high = to_decimal(raw["high"])
          low = to_decimal(raw["low"])
          qfq_factor = factor_for(qfq_factors, trade_date, qfq_cursor)
          hfq_factor = factor_for(hfq_factors, trade_date, hfq_cursor)

          {
            stock_id: stock.id,
            market: stock.market,
            trade_date: trade_date,
            open: open.round(PRICE_SCALE),
            close: close.round(PRICE_SCALE),
            high: high&.round(PRICE_SCALE),
            low: low&.round(PRICE_SCALE),
            volume: to_integer(raw["volume"]),
            qfq_open: (open / qfq_factor).round(PRICE_SCALE),
            qfq_close: (close / qfq_factor).round(PRICE_SCALE),
            qfq_high: high && (high / qfq_factor).round(PRICE_SCALE),
            qfq_low: low && (low / qfq_factor).round(PRICE_SCALE),
            qfq_factor: qfq_factor.round(FACTOR_SCALE),
            hfq_open: (open * hfq_factor).round(PRICE_SCALE),
            hfq_close: (close * hfq_factor).round(PRICE_SCALE),
            hfq_high: high && (high * hfq_factor).round(PRICE_SCALE),
            hfq_low: low && (low * hfq_factor).round(PRICE_SCALE),
            hfq_factor: hfq_factor.round(FACTOR_SCALE),
            created_at: now,
            updated_at: now
          }
        end
      end

      private

      def empty_result
        { total: 0, inserted: 0, updated: 0, bars: 0 }
      end

      def request(url)
        retries = RETRY_TIMES
        begin
          response = http_client.get(url) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = REFERER
            req.options.timeout = TIMEOUT
            req.options.open_timeout = TIMEOUT
          end

          raise RequestError, "HTTP #{response.status}" unless response.success?

          response.body
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed, RequestError => e
          # 首次请求 + RETRY_TIMES 次重试
          raise if retries.zero?

          retries -= 1
          Rails.logger.warn "[SinaMonthlyBar] 请求异常，重试中（剩余 #{retries} 次）：#{e.message}"
          sleep RETRY_INTERVAL
          retry
        end
      end

      # 取「因子事件日 ≤ 交易日」中最新的一条因子（除权日当月即生效）
      # cursor 为跨行复用的下标（因子与月K均按日期升序，单次遍历即可）
      def factor_for(factors, trade_date, cursor)
        return BigDecimal(1) if factors.empty?

        cursor[0] += 1 while cursor[0] + 1 < factors.size && factors[cursor[0] + 1][:date] <= trade_date
        factors[cursor[0]][:factor]
      end

      # 清理与本次抓取结果「同月但日期不同」的旧行：
      # 尚未走完的当月，新浪以「当前最新交易日」为日期且月内逐日推进（09-29 → 09-30），
      # 若只 upsert 会在同一月份留下多行；跨月时上月残留的部分月行（如 08-30）
      # 与本月才拿到的真实月末行（08-31）也会并存，故按「本次覆盖到的月份」整体收敛
      def cleanup_stale_dates(stock, bars)
        new_dates = bars.map { |bar| bar[:trade_date] }
        months = new_dates.map(&:beginning_of_month).uniq.sort

        deleted = stock.stock_monthly_bars
          .where(trade_date: months.first..months.last.end_of_month)
          .where.not(trade_date: new_dates)
          .delete_all
        Rails.logger.info "[SinaMonthlyBar] #{stock.symbol} 清理同月旧行 #{deleted} 条" if deleted.positive?
      end

      # 自检：同一行必须满足 后复权收盘价 ÷ 前复权收盘价 ≡ 常数（= hfq_last）
      def verify_constant_ratio(stock, bars)
        ratios = bars.filter_map do |bar|
          next if bar[:hfq_close].blank? || bar[:qfq_close].to_d.zero?

          bar[:hfq_close] / bar[:qfq_close]
        end
        return if ratios.size < 2

        expected = ratios.first
        max_deviation = ratios.map { |ratio| ((ratio - expected) / expected).abs }.max
        return if max_deviation <= RATIO_TOLERANCE

        Rails.logger.warn "[SinaMonthlyBar] #{stock.symbol} 前后复权常数关系异常，最大相对偏差 #{max_deviation}"
      end

      def parse_trade_date(value)
        Date.parse(value.to_s)
      rescue Date::Error, ArgumentError
        nil
      end

      def to_decimal(value)
        return nil if value.nil?

        str = value.to_s.strip
        return nil if str.empty?

        BigDecimal(str)
      rescue ArgumentError
        nil
      end

      def to_integer(value)
        Integer(value.to_s.strip)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end