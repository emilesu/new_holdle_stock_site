module WindowWatch
  # R2 卡片近 6 月柱形 sparkline（契约 v0.5 §四备案）：
  # 数据源 = Trae 月K库（stock_monthly_bars，后复权收盘递推 MACD，算法与 stocks#show 三联图同源——
  # DSH 月批的复权与 MACD 递推自始参照本实现，纪要 Q1/Q2 双端逐位一致）
  # 对账条款（DSH 2026-11-25 确认）：末根柱（判定月）恒以快照 hist 为准；
  # 月K库滞后（缺判定月）时以快照值补末根并标注数据截至日（lagged=true）
  # 呈现纪律：仅图形与月份，不渲染任何绝对数值（V11）
  class MonthlySparkline
    MONTHS = 6
    # EMA 预热窗口（月）：末柱恒取快照值、更早柱仅定性呈现，10 年预热后种子影响可忽略；
    # 不设限则每请求全历史 pluck（预设行+④行可达数百股），小内存服务器浪费明显（评审修复1）
    WARMUP_MONTHS = 120
    FAST, SLOW, SIGNAL = 12, 26, 9

    # values: 6 个月份槽位的柱值（前复权口径，nil=该月无数据）；末槽恒=快照 hist
    # lagged: 月K库缺判定月；cutoff: 月K库最新月份（lagged 标注用）
    Result = Struct.new(:values, :lagged, :cutoff, keyword_init: true)

    class << self
      # rows = 快照逐股行集合；返回 { code(downcase) => Result }
      def call(rows, snapshot_month:)
        # 月份格式以契约边界 SnapshotIngest 为权威源（评审修复3）
        return {} if rows.empty? || snapshot_month.to_s !~ SnapshotIngest::MONTH_FORMAT

        symbols = rows.map { |r| r.code.to_s.upcase }.uniq
        stocks = Stock.where(symbol: symbols).index_by(&:symbol)
        bars = fetch_bars(stocks.values.map(&:id), snapshot_month)

        rows.each_with_object({}) do |row, out|
          stock = stocks[row.code.to_s.upcase]
          out[row.code] = build(stock ? bars[stock.id] : nil, row, snapshot_month)
        end
      end

      private

      def fetch_bars(stock_ids, snapshot_month)
        return {} if stock_ids.empty?
        # 预热窗口内一次批量取（窗口起点=判定月首日回溯 WARMUP_MONTHS 个月；
        # hfq 因子随分红单调递增，窗口内末期因子=全局末期因子，前复权缩放不受裁剪影响）
        y, m = snapshot_month.split("-").map(&:to_i)
        start_date = Date.new(y, m, 1) - WARMUP_MONTHS.months
        StockMonthlyBar.where(stock_id: stock_ids).where(trade_date: start_date..)
                       .order(:stock_id, :trade_date)
                       .pluck(:stock_id, :trade_date, :hfq_close, :hfq_factor)
                       .each_with_object({}) do |(id, d, c, f), h|
          (h[id] ||= []) << [d.strftime("%Y-%m"), c.to_f, f.to_f]
        end
      end

      def build(bar_rows, row, snapshot_month)
        hist_by_month = to_qfq_hist(bar_rows)
        # 柱按 trade_date 升序，末根月份=库内最新月；lagged 只表「库缺判定月」，
        # 与递推可行性解耦（库仅 1 根判定月时不算滞后，评审修复2）
        latest_db_month = bar_rows&.last&.first

        slots = month_seq(snapshot_month)
        values = slots.each_with_index.map do |m, i|
          if m == snapshot_month
            row.hist.to_f # 对账条款：末根柱恒取快照值
          elsif hist_by_month.key?(m)
            hist_by_month[m]
          elsif i == slots.size - 2
            row.prev_hist.to_f # 库缺判定月前一月时，以上月快照值兜底
          end
        end

        Result.new(values: values, lagged: latest_db_month != snapshot_month, cutoff: latest_db_month)
      end

      # 后复权序列递推 hist 后 ÷ 末期后复权因子 = 前复权口径（与 stocks_controller#fetch_monthly_trend 一致）
      def to_qfq_hist(bar_rows)
        return {} if bar_rows.nil? || bar_rows.size < 2
        closes = bar_rows.map { |(_m, c, _f)| c }
        raw = compute_hist(closes)
        last_factor = bar_rows.map { |(_m, _c, f)| f }.compact.max
        scale = last_factor.to_f > 0 ? 1.0 / last_factor : 1.0
        bar_rows.each_with_index.to_h { |(m, _c, _f), i| [m, raw[i] * scale] }
      end

      def compute_hist(closes)
        fast = ema(closes, FAST)
        slow = ema(closes, SLOW)
        dif = fast.each_with_index.map { |v, i| v - slow[i] }
        dea = ema(dif, SIGNAL)
        dif.each_with_index.map { |v, i| 2 * (v - dea[i]) }
      end

      # 指数移动平均：α = 2/(n+1)，以首值为种子递推（与东财/同花顺口径一致）
      def ema(values, period)
        alpha = 2.0 / (period + 1)
        previous = nil
        values.map do |value|
          previous = previous.nil? ? value : alpha * value + (1 - alpha) * previous
        end
      end

      def month_seq(month, n = MONTHS)
        y, m = month.split("-").map(&:to_i)
        idx = y * 12 + m - 1
        (0...n).map do |i|
          t = idx - n + 1 + i
          format("%04d-%02d", t / 12, t % 12 + 1)
        end
      end
    end
  end
end
