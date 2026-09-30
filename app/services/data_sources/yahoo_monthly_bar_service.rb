module DataSources
  # Yahoo 港股/美股月K抓取服务（三联图扩展，见方案 15_港股美股三联图_实施方案）
  #
  # 数据流：Yahoo v8 chart 月K（interval=1mo + period1/period2 显式窗口）
  #         → close ÷ adjclose 推导复权因子 → 本地等比换算三套价 → 落库 stock_monthly_bars
  #         → 因子跳变（除权）事件月另取该窗口日线逐日复权聚合（镜像 Sina 版 correct_event_months）
  #
  # 因子语义与新浪 qfq/hfq 同构（方案 §2.3 实测，0700.HK / BRK-B / GE）：
  #   qf_m = 不复权收盘 ÷ adjclose（Yahoo 原生比值，最新月 ≈ 1.0）
  #   qfq_factor_m = qf_m ÷ qf_latest（最新月归一 = 1 → 前复权价 = 不复权价 ÷ qfq_factor）
  #   hfq_factor_m = qf_first ÷ qf_m（首月归一 = 1 → 后复权价 = 不复权价 × hfq_factor）
  #   恒等式：后复权价 ÷ 前复权价 ≡ qf_first ÷ qf_latest（常数，verify_constant_ratio 自检）
  #
  # ⚠️ 采样陷阱（2026-09-30 实测）：range=max 会被静默降采样
  #   （interval=1d&range=max 只回 365 根月间隔；GE interval=1mo&range=max 退化为 3 个月间隔），
  #   必须用 period1/period2 显式窗口。
  #
  # trade_date 归一（2026-10-01 试点实测修正）：Yahoo 月K时间戳 = 数据月「1 日 00:00 交易所当地时间」
  #   （港股显示为上月末 16:00 utc；美股显示为月初 04:00 utc），必须用 meta.gmtoffset 换算回
  #   当地时间再取日历月末；直接用 UTC 日期会把整条月线前移一个月（4月数据错标3月）。
  #   当月进行中会被拆成「月初缓存根 + 最新盘中根」两根同月 → 按月合并（否则 upsert 同键两行报错）；
  #   增量模式下「当月 + 上月」行整行覆盖（对齐新浪「当月行逐日推进重写」语义，月末后自愈为完整数据）。
  #
  # 重算策略（与 A 股 D9/D14 对齐）：
  #   :full        —— 全量重算并覆盖所有列（首次建库）
  #   :incremental —— 已有历史行只更新前复权列，后复权列保持不动；事件月修正仅针对待修行
  class YahooMonthlyBarService
    CHART_BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 20
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    # 请求间隔（秒），避免触发数据源限流（批量编排在 MonthlyBarBatchService 侧执行）
    REQUEST_INTERVAL = 0.3

    # period1 = 0 时 Yahoo 钳制到 1970-01-01，即月K历史深度上限（方案 H6，可接受）
    PERIOD1_FULL = 0

    PRICE_SCALE = 4
    FACTOR_SCALE = 10
    # 常数比值自检的相对误差容差
    RATIO_TOLERANCE = 1e-4
    # 因子跳变判定容差：qf = close ÷ adjclose，两列各自舍入后同月间比值存在 ~1e-7 量级噪声，
    # 必须用相对容差（真实除权因子跳变至少百分之几，远大于该值），否则每月都被误判为事件月
    FACTOR_EPSILON = 1e-6

    # HTTP 非 2xx 响应（纳入重试范围）
    class RequestError < StandardError; end
    # 404：退市/窝轮等无数据符号，不重试，直接跳过本只
    class SymbolNotFound < StandardError; end

    # 冲突时需要更新的列（created_at 不参与覆盖）
    FULL_UPDATE_COLUMNS = %i[
      market open close high low volume
      qfq_open qfq_close qfq_high qfq_low qfq_factor
      hfq_open hfq_close hfq_high hfq_low hfq_factor
      updated_at
    ].freeze

    # 增量模式：已有历史行只重写前复权列（前复权随时间整段变化），后复权列「只增不改」
    INCREMENTAL_UPDATE_COLUMNS = %i[qfq_open qfq_close qfq_high qfq_low qfq_factor updated_at].freeze

    # 增量模式下「本轮新修正的事件月」行需要额外落库后复权价列
    EVENT_MONTH_UPDATE_COLUMNS = %i[
      qfq_open qfq_close qfq_high qfq_low
      hfq_open hfq_close hfq_high hfq_low updated_at
    ].freeze

    class << self
      # HTTP客户端，默认为Faraday，测试时可替换
      attr_writer :http_client

      def http_client
        @http_client || Faraday
      end

      # 抓取单只股票并落库；404（退市/无数据）返回空结果不抛异常
      # 返回 { total:, inserted:, updated:, bars: }
      def refresh(stock, mode: :full)
        symbol = yahoo_symbol(stock)
        if symbol.nil?
          Rails.logger.warn "[YahooMonthlyBar] #{stock.market}/#{stock.symbol} 无法转换为 Yahoo 代码，跳过"
          return empty_result
        end

        month_bars = fetch_month_bars(symbol)
        if month_bars.empty?
          Rails.logger.warn "[YahooMonthlyBar] #{symbol} 未获取到月K数据"
          return empty_result
        end

        bars = build_bars(stock, month_bars)
        return empty_result if bars.empty?

        qf_first, qf_latest = first_and_latest_factor(month_bars)
        corrected_dates = correct_event_months(stock, bars, month_bars, qf_first, qf_latest, mode: mode)

        verify_constant_ratio(stock, bars)

        before = stock.stock_monthly_bars.count
        if mode == :incremental
          # 当月进行中行随逐日合并推进、上月行刚走完拿到完整根，原始 OHLCV/量都在变化 → 整行覆盖自愈；
          # 更早历史行只重写前复权列，后复权「只增不改」（hfq 以上市首日归一，重算值本就相同，
          # 但历史行可能含已修正的事件月聚合值，整行覆盖会退回单因子值，故必须排除）
          window = Date.current.end_of_month - 1.month
          recent, historical = bars.partition { |bar| bar[:trade_date] >= window }
          if historical.any?
            stock.stock_monthly_bars.upsert_all(
              historical,
              unique_by: %i[stock_id trade_date],
              update_only: INCREMENTAL_UPDATE_COLUMNS,
              record_timestamps: false
            )
          end
          if recent.any?
            stock.stock_monthly_bars.upsert_all(
              recent,
              unique_by: %i[stock_id trade_date],
              update_only: FULL_UPDATE_COLUMNS,
              record_timestamps: false
            )
          end
          # 本轮修正过的事件月行：后复权价列也要覆盖（其余行后复权保持「只增不改」）
          if corrected_dates.any?
            corrected_bars = bars.select { |bar| corrected_dates.include?(bar[:trade_date]) }
            stock.stock_monthly_bars.upsert_all(
              corrected_bars,
              unique_by: %i[stock_id trade_date],
              update_only: EVENT_MONTH_UPDATE_COLUMNS,
              record_timestamps: false
            )
          end
        else
          stock.stock_monthly_bars.upsert_all(
            bars,
            unique_by: %i[stock_id trade_date],
            update_only: FULL_UPDATE_COLUMNS,
            record_timestamps: false
          )
        end
        after = stock.stock_monthly_bars.count
        inserted = after - before

        { total: bars.size, inserted: inserted, updated: bars.size - inserted, bars: bars.size }
      rescue SymbolNotFound => e
        Rails.logger.warn "[YahooMonthlyBar] #{stock.symbol} Yahoo 无此标的（可能退市）：#{e.message}"
        empty_result
      end

      # 库内 symbol → Yahoo 代码
      #   HK："00700.HK" → "0700.HK"（Yahoo 港股为 4 位数字，5 位形式实测 404）
      #   US："BRK.B" / "BF.A" → "BRK-B" / "BF-B"（点号与斜杠均映射为连字符）
      def yahoo_symbol(stock)
        case stock.market
        when "HK"
          digits = stock.symbol.to_s[/\A0*(\d{1,4})\.HK\z/i, 1]
          digits && format("%04d.HK", digits.to_i)
        when "US"
          symbol = stock.symbol.to_s.strip
          return nil if symbol.empty?

          symbol.upcase.tr("./", "--")
        end
      end

      # 月K全历史：[{ trade_date: 日历月末 Date, open:, high:, low:, close:, volume:, qf: BigDecimal }]
      # qf = 不复权收盘 ÷ adjclose（该月月末因子）；adjclose 缺失的月份沿用上一有效 qf（因子分段常数）
      def fetch_month_bars(symbol)
        url = chart_url(symbol, "1mo", PERIOD1_FULL, Time.now.to_i)
        parse_bars(request(url))
      rescue JSON::ParserError => e
        Rails.logger.error "[YahooMonthlyBar] #{symbol} 月K解析失败：#{e.message}"
        []
      end

      # 日线（事件月修正用）：period1 起的全部日线
      # 返回 [{ date:, open:, high:, low:, close:, qf: }]，按日期升序
      def fetch_daily_bars(symbol, period1)
        url = chart_url(symbol, "1d", period1, Time.now.to_i)
        data = JSON.parse(request(url))
        result = extract_result(data)
        return [] if result.nil?

        gmtoffset = result.dig("meta", "gmtoffset").to_i
        timestamps = Array(result["timestamp"])
        quote = Array(result.dig("indicators", "quote"))[0] || {}
        adjcloses = Array(result.dig("indicators", "adjclose"))[0]&.fetch("adjclose") || []
        closes = Array(quote["close"])

        carried = nil
        rows = timestamps.each_with_index.filter_map do |ts, i|
          next if ts.nil?

          # 与月K同源：时间戳按 meta.gmtoffset 换算回交易所当地时间再取日期
          date = Time.at(ts.to_i + gmtoffset).utc.to_date
          close = to_decimal(closes[i])
          next if close.nil?

          adj = to_decimal(adjcloses[i])
          carried = (close / adj) if adj.present? && !adj.zero?
          next if carried.nil?

          {
            date: date,
            open: to_decimal(quote["open"]&.[](i)),
            high: to_decimal(quote["high"]&.[](i)),
            low: to_decimal(quote["low"]&.[](i)),
            close: close,
            qf: carried
          }
        end
        dedup_daily_by_date(rows)
      rescue JSON::ParserError => e
        Rails.logger.error "[YahooMonthlyBar] #{symbol} 日线解析失败：#{e.message}"
        []
      end

      # 月K序列 → 落库行数组（单因子换算；事件月由 correct_event_months 覆盖）
      def build_bars(stock, month_bars, now: Time.current)
        qf_first, qf_latest = first_and_latest_factor(month_bars)
        return [] if qf_first.nil? || qf_latest.nil? || qf_latest.zero?

        month_bars.filter_map do |bar|
          open = bar[:open]
          close = bar[:close]
          next if open.nil? || close.nil?

          qfq_factor = bar[:qf] / qf_latest
          hfq_factor = qf_first / bar[:qf]
          high = bar[:high]
          low = bar[:low]

          {
            stock_id: stock.id,
            market: stock.market,
            trade_date: bar[:trade_date],
            open: open.round(PRICE_SCALE),
            close: close.round(PRICE_SCALE),
            high: high&.round(PRICE_SCALE),
            low: low&.round(PRICE_SCALE),
            volume: bar[:volume],
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

      def chart_url(symbol, interval, period1, period2)
        "#{CHART_BASE_URL}/#{symbol}?interval=#{interval}&period1=#{period1}&period2=#{period2}"
      end

      def request(url)
        retries = RETRY_TIMES
        begin
          response = http_client.get(url) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.options.timeout = TIMEOUT
            req.options.open_timeout = TIMEOUT
          end

          # 404 = 无此标的（退市/窝轮），重试无意义，直接抛出由 refresh 跳过
          raise SymbolNotFound, "HTTP #{response.status}" if response.status == 404
          raise RequestError, "HTTP #{response.status}" unless response.success?

          body = response.body
          # HTTP 200 但 body 携带 chart.error（Yahoo 的 Not Found 也可能走这里）
          error = JSON.parse(body).dig("chart", "error") rescue nil
          raise SymbolNotFound, error["code"].to_s if error.present?

          body
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed, RequestError => e
          # 首次请求 + RETRY_TIMES 次重试
          raise if retries.zero?

          retries -= 1
          Rails.logger.warn "[YahooMonthlyBar] 请求异常，重试中（剩余 #{retries} 次）：#{e.message}"
          sleep RETRY_INTERVAL
          retry
        end
      end

      def parse_bars(body)
        result = extract_result(JSON.parse(body))
        return [] if result.nil?

        gmtoffset = result.dig("meta", "gmtoffset").to_i
        timestamps = Array(result["timestamp"])
        quote = Array(result.dig("indicators", "quote"))[0] || {}
        adjcloses = Array(result.dig("indicators", "adjclose"))[0]&.fetch("adjclose") || []
        closes = Array(quote["close"])

        carried = nil
        bars = timestamps.each_with_index.filter_map do |ts, i|
          next if ts.nil?

          date = Time.at(ts.to_i + gmtoffset).utc.to_date
          close = to_decimal(closes[i])
          next if close.nil?

          adj = to_decimal(adjcloses[i])
          carried = (close / adj) if adj.present? && !adj.zero?
          next if carried.nil? # 全序列都拿不到 adjclose 时整只跳过，避免静默写未复权口径

          {
            trade_date: date.end_of_month,
            open: to_decimal(quote["open"]&.[](i)),
            high: to_decimal(quote["high"]&.[](i)),
            low: to_decimal(quote["low"]&.[](i)),
            close: close,
            volume: to_integer(quote["volume"]&.[](i)),
            qf: carried
          }
        end
        merge_bars_by_month(bars)
      end

      # 同月多根合并（当月进行中 = 「月初缓存根 + 最新盘中根」两根同月）：
      # 开=首根、高/低=极值、收/因子=末根、量=求和；已完成月份只有一根，等价于原样保留
      def merge_bars_by_month(bars)
        bars.each_with_object({}) do |bar, acc|
          previous = acc[bar[:trade_date]]
          acc[bar[:trade_date]] =
            if previous.nil?
              bar
            else
              {
                trade_date: bar[:trade_date],
                open: previous[:open],
                high: [previous[:high], bar[:high]].compact.max,
                low: [previous[:low], bar[:low]].compact.min,
                close: bar[:close],
                volume: (previous[:volume] || 0) + (bar[:volume] || 0),
                qf: bar[:qf]
              }
            end
        end.values.sort_by { |b| b[:trade_date] }
      end

      # 同日多根（盘中最新根与缓存根重复）：保留末根，其 close/qf 为当日最终值
      def dedup_daily_by_date(rows)
        rows.each_with_object({}) { |row, acc| acc[row[:date]] = row }.values.sort_by { |d| d[:date] }
      end

      def extract_result(data)
        result = data.dig("chart", "result")
        return nil if result.blank?

        result[0]
      end

      def first_and_latest_factor(month_bars)
        valid = month_bars.reject { |b| b[:qf].nil? }
        [valid.first&.dig(:qf), valid.last&.dig(:qf)]
      end

      # 除权事件月修正：把「因子跳变落在月中」的月份改为按日复权聚合（镜像 Sina 版）
      #
      #   单因子换算只对整月因子不变的月份成立；事件月内 open/high/low 可能发生在
      #   除权日之前，须用除权前的旧因子换算。聚合规则与 A 股一致：
      #   open=首日、high=逐日复权高的最大值、low=最小值、close=末日。
      #
      #   full 模式修正全部事件月；incremental 模式只修正「库里仍是旧算法值」
      #   或「未落库 / 当月进行中」的行，日线请求窗口取最早待修事件月月初。
      #   日线请求失败时保持单因子值降级落库，下一轮增量会因「仍是旧算法值」被重新识别修正，
      #   具备自愈能力。
      #
      # 返回本轮实际修正过的 trade_date 数组。
      def correct_event_months(stock, bars, month_bars, qf_first, qf_latest, mode:)
        return [] if qf_first.nil? || qf_latest.nil? || qf_latest.zero?

        event_dates = []
        month_bars.each_with_index do |bar, i|
          next if i.zero?

          previous = month_bars[i - 1]
          # 相对容差：qf 在 1.0 附近时绝对差≈相对差，但高价股因子可达数十倍，
          # 绝对阈值会漏判/误判；真实除权跳变相对变化至少千分之几，噪声约 1e-7
          next if previous[:qf].nil? || previous[:qf].zero?

          event_dates << bar[:trade_date] if ((bar[:qf] - previous[:qf]) / previous[:qf]).abs > FACTOR_EPSILON
        end
        affected = bars.select { |bar| event_dates.include?(bar[:trade_date]) }
        return [] if affected.empty?

        pending =
          if mode == :incremental
            pick_uncorrected_bars(stock, affected, bars, qf_first, qf_latest)
          else
            affected
          end
        return [] if pending.empty?

        earliest = pending.map { |bar| bar[:trade_date].beginning_of_month }.min
        period1 = Time.utc(earliest.year, earliest.month, 1).to_i
        daily =
          begin
            fetch_daily_bars(yahoo_symbol(stock), period1)
          rescue StandardError => e
            Rails.logger.error "[YahooMonthlyBar] #{stock.symbol} 日线抓取失败：#{e.message}"
            []
          end
        if daily.empty?
          Rails.logger.warn "[YahooMonthlyBar] #{stock.symbol} 日线缺失，事件月暂按单因子落库，下次增量自动重试"
          return []
        end

        corrected_dates = []
        pending.each do |bar|
          month_begin = bar[:trade_date].beginning_of_month
          month_days = daily.select { |d| d[:date] >= month_begin && d[:date] <= bar[:trade_date] }
          next if month_days.empty?

          apply_event_month_correction(bar, month_days, qf_first, qf_latest)
          corrected_dates << bar[:trade_date]
        end
        corrected_dates
      end

      # 增量模式的事件月分流（与 Sina 版同构）：
      #   需要重新修正：未落库的新行 / 当月进行中的行 / 库里 hfq_open 仍是「不复权open × 月末因子」旧算法值的行
      #   已修正过：用库里 hfq 列按恒等式 前复权 = 后复权 ÷ 常数(hfq_last) 推导出本轮要重写的前复权列
      def pick_uncorrected_bars(stock, affected, bars, qf_first, qf_latest)
        stored_rows = stock.stock_monthly_bars
          .where(trade_date: affected.map { |bar| bar[:trade_date] })
          .index_by(&:trade_date)
        latest_date = bars.last[:trade_date]
        hfq_last = qf_first / qf_latest

        affected.select do |bar|
          row = stored_rows[bar[:trade_date]]
          if row.nil? || row.hfq_open.nil? || bar[:trade_date] == latest_date || row.hfq_open == bar[:hfq_open]
            true
          else
            # 已修正过：回填库内 hfq 聚合值（「当月+上月」行走整行覆盖 upsert，
            # 不回填会把逐日聚合修正值退回本轮重算的单因子值）；
            # 前复权 = 后复权 ÷ hfq_last（常数关系，逐字段成立）
            bar[:hfq_open] = row.hfq_open
            bar[:hfq_close] = row.hfq_close
            bar[:hfq_high] = row.hfq_high
            bar[:hfq_low] = row.hfq_low
            bar[:qfq_open] = (row.hfq_open / hfq_last).round(PRICE_SCALE)
            bar[:qfq_close] = (row.hfq_close / hfq_last).round(PRICE_SCALE)
            bar[:qfq_high] = row.hfq_high && (row.hfq_high / hfq_last).round(PRICE_SCALE)
            bar[:qfq_low] = row.hfq_low && (row.hfq_low / hfq_last).round(PRICE_SCALE)
            false
          end
        end
      end

      # 用「该月逐日不复权价 × 当日因子」聚合结果覆盖事件月的两套复权价
      def apply_event_month_correction(bar, month_days, qf_first, qf_latest)
        first = month_days.first
        last = month_days.last

        qfq_high = month_days.filter_map { |d| d[:high] && (d[:high] * qf_latest / d[:qf]) }.max
        qfq_low = month_days.filter_map { |d| d[:low] && (d[:low] * qf_latest / d[:qf]) }.min
        hfq_high = month_days.filter_map { |d| d[:high] && (d[:high] * qf_first / d[:qf]) }.max
        hfq_low = month_days.filter_map { |d| d[:low] && (d[:low] * qf_first / d[:qf]) }.min

        bar[:qfq_open] = first[:open] && (first[:open] * qf_latest / first[:qf]).round(PRICE_SCALE)
        bar[:qfq_close] = (last[:close] * qf_latest / last[:qf]).round(PRICE_SCALE)
        bar[:qfq_high] = qfq_high && qfq_high.round(PRICE_SCALE)
        bar[:qfq_low] = qfq_low && qfq_low.round(PRICE_SCALE)
        bar[:hfq_open] = first[:open] && (first[:open] * qf_first / first[:qf]).round(PRICE_SCALE)
        bar[:hfq_close] = (last[:close] * qf_first / last[:qf]).round(PRICE_SCALE)
        bar[:hfq_high] = hfq_high && hfq_high.round(PRICE_SCALE)
        bar[:hfq_low] = hfq_low && hfq_low.round(PRICE_SCALE)
      end

      # 自检：同一行必须满足 后复权收盘价 ÷ 前复权收盘价 ≡ 常数（= qf_first ÷ qf_latest）
      def verify_constant_ratio(stock, bars)
        ratios = bars.filter_map do |bar|
          next if bar[:hfq_close].blank? || bar[:qfq_close].to_d.zero?

          bar[:hfq_close] / bar[:qfq_close]
        end
        return if ratios.size < 2

        expected = ratios.first
        max_deviation = ratios.map { |ratio| ((ratio - expected) / expected).abs }.max
        return if max_deviation <= RATIO_TOLERANCE

        Rails.logger.warn "[YahooMonthlyBar] #{stock.symbol} 前后复权常数关系异常，最大相对偏差 #{max_deviation}"
      end

      def to_decimal(value)
        return nil if value.nil?

        case value
        when Numeric then BigDecimal(value.to_s)
        when String
          str = value.strip
          str.empty? ? nil : BigDecimal(str)
        end
      rescue ArgumentError
        nil
      end

      def to_integer(value)
        return nil if value.nil?

        Integer(value.to_f.round)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
