require "test_helper"

# Yahoo 港股/美股月K抓取服务：符号转换、因子推导、月末归一、事件月修正、增量策略
# fixture 语义与 Sina 版对齐：3 个月K（开10 高11 低9 收10），3 月除权一次（qf 2 → 1）
#
# 时间戳约定（2026-10-01 试点实测修正）：Yahoo 月K ts = 数据月「1 日 00:00 交易所当地时间」，
# fixture 的 days 即当地日历日，ts = utc(days) - gmtoffset，使「naive UTC 日期」与「当地时间日期」
# 分属不同月份，回归验证必须按 meta.gmtoffset 换算（否则整条月线前移一个月）。
class YahooMonthlyBarServiceTest < ActiveSupport::TestCase
  Service = DataSources::YahooMonthlyBarService

  JAN = Date.new(2024, 1, 31)
  FEB = Date.new(2024, 2, 29)
  MAR = Date.new(2024, 3, 31)
  APR = Date.new(2024, 4, 30)

  HK_GMT_OFFSET = 28_800   # Asia/Hong_Kong UTC+8
  US_GMT_OFFSET = -14_400  # America/New_York EDT UTC-4

  setup do
    @stock = Stock.create!(symbol: "00700.HK", name: "月K测试", market: "HK")
    Service.http_client = nil
  end

  teardown do
    Service.http_client = nil
  end

  # ====================================================
  # 符号转换（方案 §2.2：Yahoo 港股 4 位、美股点号转连字符）
  # ====================================================
  test "库内代码转 Yahoo 代码：港股补足 4 位、美股点号/斜杠转连字符" do
    assert_equal "0700.HK", Service.yahoo_symbol(Stock.new(symbol: "00700.HK", market: "HK"))
    assert_equal "1211.HK", Service.yahoo_symbol(Stock.new(symbol: "01211.HK", market: "HK"))
    assert_equal "BRK-B", Service.yahoo_symbol(Stock.new(symbol: "BRK.B", market: "US"))
    assert_equal "BF-A", Service.yahoo_symbol(Stock.new(symbol: "BF.A", market: "US"))
    assert_equal "AAPL", Service.yahoo_symbol(Stock.new(symbol: "AAPL", market: "US"))
    assert_nil Service.yahoo_symbol(Stock.new(symbol: "SH600519", market: "CN"))
  end

  # ====================================================
  # 因子推导与恒等式（qf = close ÷ adjclose，方案 §2.3）
  # ====================================================
  test "因子推导：前复权因子最新月归一、后复权因子首月归一" do
    bars = Service.build_bars(@stock, month_bars_fixture)

    assert_equal BigDecimal("1.0"), bars[0][:hfq_factor], "首月后复权因子应为 1"
    assert_equal BigDecimal("1.0"), bars[-1][:qfq_factor], "最新月前复权因子应为 1"
    # qf [2,2,1]：首期 qfq_factor = 2/1 = 2 → 10 ÷ 2 = 5；末期 hfq_factor = 2/1 = 2 → 10 × 2 = 20
    assert_equal BigDecimal("5.0"), bars[0][:qfq_close]
    assert_equal BigDecimal("10.0"), bars[0][:hfq_close]
    assert_equal BigDecimal("20.0"), bars[2][:hfq_close]
  end

  test "恒等式：后复权价 ÷ 前复权价 恒等于 qf_first ÷ qf_latest" do
    bars = Service.build_bars(@stock, month_bars_fixture)

    ratios = bars.map { |bar| bar[:hfq_close] / bar[:qfq_close] }
    assert_equal 1, ratios.uniq.size, "比值应为常数，实际：#{ratios.uniq.inspect}"
    assert_equal BigDecimal("2.0"), ratios.first
  end

  # ====================================================
  # trade_date 月末归一（试点错位 bug 回归：必须按 meta.gmtoffset 换算当地时间）
  # ====================================================
  test "月末归一：港股时间戳（utc=上月末16:00）按 gmtoffset 换算后归到数据月月末" do
    # 数据月 2024-03 → ts = 03-01 00:00 HKT = 02-29 16:00 UTC；
    # 若按 naive UTC 日期会错归到 02-29（整条月线前移一个月，即试点「港股近月错位」根因）
    Service.http_client = build_client("interval=1mo" => month_body(days: %w[2024-03-01]))
    hk_bars = Service.fetch_month_bars("0700.HK")
    assert_equal Date.new(2024, 3, 31), hk_bars.first[:trade_date]
  end

  test "月末归一：美股时间戳（utc=月初04:00）同样归到数据月日历月末" do
    Service.http_client = build_client(
      "interval=1mo" => month_body(days: %w[2024-03-01], gmtoffset: US_GMT_OFFSET)
    )
    us_bars = Service.fetch_month_bars("AAPL")
    assert_equal Date.new(2024, 3, 31), us_bars.first[:trade_date]
  end

  # ====================================================
  # 当月拆根合并（试点美股 0 入库根因：同月两根 → upsert 同键报错）
  # ====================================================
  test "同月两根（月初缓存根+盘中最新根）按月合并为一根" do
    Service.http_client = build_client(
      "interval=1mo" => month_body(days: %w[2024-03-01 2024-03-29], closes: [10.0, 12.0], adjcloses: [5.0, 6.0])
    )
    bars = Service.fetch_month_bars("0700.HK")

    assert_equal 1, bars.size
    merged = bars.first
    assert_equal MAR, merged[:trade_date]
    assert_equal BigDecimal("10.0"), merged[:open], "开=首根"
    assert_equal BigDecimal("13.0"), merged[:high], "高=两根极值"
    assert_equal BigDecimal("9.0"), merged[:low], "低=两根极值"
    assert_equal BigDecimal("12.0"), merged[:close], "收=末根"
    assert_equal 3000, merged[:volume], "量=两根求和"
    assert_equal BigDecimal("2.0"), merged[:qf], "因子=末根（12 ÷ 6）"
  end

  test "当月拆根入库不触发 ON CONFLICT 同键报错（试点美股零入库回归）" do
    Service.http_client = build_client(
      "interval=1mo" => month_body(
        days: %w[2024-01-01 2024-02-01 2024-03-01 2024-03-29],
        closes: [10.0, 10.0, 10.0, 11.0],
        adjcloses: [5.0, 5.0, 5.0, 5.5]
      )
    )

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, result[:total]
    assert_equal [JAN, FEB, MAR], @stock.stock_monthly_bars.order(:trade_date).pluck(:trade_date)
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("11.0"), march.close, "合并后收盘取盘中最新根"
  end

  # ====================================================
  # 采样陷阱回归：必须用 period1/period2 显式窗口，禁止 range=max
  # ====================================================
  test "请求 URL 必须携带 period1/period2 显式窗口，不得出现 range 参数" do
    stub_http
    Service.refresh(@stock, mode: :full)

    urls = http_calls
    assert urls.any?, "应发出月K请求"
    urls.each do |url|
      assert_includes url, "period1="
      assert_includes url, "period2="
      refute_includes url, "range=", "range=max 会被 Yahoo 静默降采样（方案 §2.3 陷阱）"
    end
  end

  # ====================================================
  # 落库
  # ====================================================
  test "全量 refresh 落库 3 根月K，trade_date 归一到日历月末" do
    stub_http

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, result[:total]
    assert_equal [JAN, FEB, MAR], @stock.stock_monthly_bars.order(:trade_date).pluck(:trade_date)
  end

  # ====================================================
  # 除权事件月修正（镜像 A 股 correct_event_months）
  # ====================================================
  test "因子舍入噪声（相对差 ~1e-7）不得误判为事件月（试点每月误触日线回归）" do
    # qf = [2, 1.9999998, 1.9999996]：相邻月相对变化约 1e-7，远小于真实除权跳变
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01],
                                adjcloses: [5.0, 5.0000005, 5.0000010]))

    Service.refresh(@stock, mode: :full)

    assert Service.http_client.calls.none? { |url| url.include?("interval=1d") },
           "因子噪声不应触发事件月日线修正"
  end

  test "全量模式：因子月中跳变时，事件月按逐日因子聚合而非月末单一因子" do
    stub_http
    Service.refresh(@stock, mode: :full)

    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    # 03-01 开盘在除权前（qf=2）：前复权 = 10 × 1 ÷ 2 = 5；月末单一因子会错算成 10
    assert_equal BigDecimal("5.0"), march.qfq_open
    # 复权后 high = max(11×1/2, 11×1/1) = 11；low = min(9×1/2, 9×1/1) = 4.5
    assert_equal BigDecimal("11.0"), march.qfq_high
    assert_equal BigDecimal("4.5"), march.qfq_low
    # 收盘在除权之后：与单因子结果一致
    assert_equal BigDecimal("10.0"), march.qfq_close
    # 后复权同理：open = 10 × 旧口径（qf_first/qf=2/2=1）= 10，而非 10 × 2
    assert_equal BigDecimal("10.0"), march.hfq_open
    assert_equal BigDecimal("22.0"), march.hfq_high
    assert_equal BigDecimal("9.0"), march.hfq_low
    assert_equal BigDecimal("20.0"), march.hfq_close
    # 常数不变量仍成立
    assert_equal BigDecimal("2.0"), march.hfq_close / march.qfq_close
  end

  test "全量模式：非事件月不受影响，仍按单一因子换算" do
    stub_http
    Service.refresh(@stock, mode: :full)

    jan = @stock.stock_monthly_bars.find_by(trade_date: JAN)
    assert_equal BigDecimal("5.0"), jan.qfq_open   # 10 ÷ 2
    assert_equal BigDecimal("10.0"), jan.hfq_open  # 10 × 1
  end

  test "日线抓取失败时事件月降级为单因子落库，不中断本只股票" do
    stub_http(daily: "notjson")

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, result[:total]
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("10.0"), march.qfq_open, "降级时保持单因子换算值"
    assert_equal BigDecimal("20.0"), march.hfq_open
  end

  test "增量模式：已修正的历史事件月不再请求日线，前复权按 后复权÷常数 推导" do
    four = %w[2024-01-01 2024-02-01 2024-03-01 2024-04-01]
    stub_http(month: month_body(days: four, adjcloses: [5.0, 5.0, 10.0, 10.0]))
    Service.refresh(@stock, mode: :full)
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("10.0"), march.hfq_open, "全量修正后 hfq_open = 10 × 旧口径1"

    # 同一数据源再跑增量：3 月是已修正的历史事件月（4 月才是最新行），不应再请求日线
    stub_http(month: month_body(days: four, adjcloses: [5.0, 5.0, 10.0, 10.0]))
    Service.refresh(@stock, mode: :incremental)

    assert Service.http_client.calls.none? { |url| url.include?("interval=1d") },
           "已修正的事件月不应重复请求日线"
    march.reload
    assert_equal BigDecimal("10.0"), march.hfq_open, "已修正的历史后复权列保持只增不改"
    assert_equal BigDecimal("5.0"), march.qfq_open, "前复权 = 后复权 ÷ hfq_last(2) = 5"
  end

  test "增量模式：历史后复权列不被覆盖，前复权列整段重写" do
    stub_http
    Service.refresh(@stock, mode: :full)

    jan = @stock.stock_monthly_bars.find_by(trade_date: JAN)
    assert_equal BigDecimal("10.0"), jan.hfq_close
    assert_equal BigDecimal("5.0"), jan.qfq_close

    # 因子序列整体变为常数 3（无事件月）：前复权全部归一；后复权列在增量模式下不得覆盖
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01], adjcloses: [10.0 / 3, 10.0 / 3, 10.0 / 3]))
    Service.refresh(@stock, mode: :incremental)

    jan.reload
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("10.0"), jan.hfq_close, "增量模式下历史后复权列不应被覆盖"
    assert_equal BigDecimal("10.0"), jan.qfq_close, "增量模式下前复权列应整段重写"
    assert_equal BigDecimal("20.0"), march.hfq_close, "事件月后复权列同样保持不动"
    assert_equal BigDecimal("10.0"), march.qfq_close
  end

  test "增量模式：当月与上月行整行覆盖原始列，更早历史行原始列保持不动" do
    d_old = (Date.current - 2.months).beginning_of_month
    d_prev = (Date.current - 1.month).beginning_of_month
    d_cur = Date.current.beginning_of_month
    days = [d_old, d_prev, d_cur].map { |d| d.strftime("%Y-%m-%d") }

    # 首轮全量：三个月收盘均 10，qf 恒为 2（无事件月）
    stub_http(month: month_body(days: days, adjcloses: [5.0, 5.0, 5.0]))
    Service.refresh(@stock, mode: :full)

    # 次轮增量：当月推进到 12、上月补全为 11、更早月源数据「回跳」到 99（模拟源端修订）
    stub_http(month: month_body(days: days, closes: [99.0, 11.0, 12.0], adjcloses: [49.5, 5.5, 6.0]))
    Service.refresh(@stock, mode: :incremental)

    old_row = @stock.stock_monthly_bars.find_by(trade_date: d_old.end_of_month)
    assert_equal BigDecimal("10.0"), old_row.close, "更早历史行原始列不被增量覆盖"
    assert_equal BigDecimal("10.0"), old_row.hfq_close, "更早历史行后复权保持只增不改"
    assert_equal BigDecimal("99.0"), old_row.qfq_close, "前复权列仍整段重写"

    prev_row = @stock.stock_monthly_bars.find_by(trade_date: d_prev.end_of_month)
    assert_equal BigDecimal("11.0"), prev_row.close, "上月行整行覆盖（月末后自愈为完整数据）"

    cur_row = @stock.stock_monthly_bars.find_by(trade_date: d_cur.end_of_month)
    assert_equal BigDecimal("12.0"), cur_row.close, "当月行整行覆盖（对齐新浪当月逐日推进重写语义）"
  end

  test "增量模式：窗口内（上月）已修正事件月的 hfq 聚合值不被整行覆盖退回" do
    d_old = (Date.current - 2.months).beginning_of_month
    d_prev = (Date.current - 1.month).beginning_of_month
    d_cur = Date.current.beginning_of_month
    days = [d_old, d_prev, d_cur].map { |d| d.strftime("%Y-%m-%d") }

    # qf [2,1,1]：除权落在「上月」月中；上月日线两根：月初（除权前 qf=2）与月中（除权后 qf=1）
    month = month_body(days: days, adjcloses: [5.0, 10.0, 10.0])
    daily = month_body(days: [d_prev.strftime("%Y-%m-%d"), (d_prev + 15).strftime("%Y-%m-%d")],
                       adjcloses: [5.0, 10.0])

    # 首轮全量：上月为事件月 → 日线聚合修正，hfq_open = 10 × (qf_first 2 ÷ 除权前 2) = 10
    #（月末单一因子会错算成 10 × 2/1 = 20）
    stub_http(month: month, daily: daily)
    Service.refresh(@stock, mode: :full)
    prev_row = @stock.stock_monthly_bars.find_by(trade_date: d_prev.end_of_month)
    assert_equal BigDecimal("10.0"), prev_row.hfq_open, "首轮应完成日线聚合修正"

    # 次轮增量：上月落在「当月+上月」整行覆盖窗口，且已修正 → 不应请求日线，hfq 聚合值必须保留
    stub_http(month: month, daily: daily)
    Service.refresh(@stock, mode: :incremental)

    assert Service.http_client.calls.none? { |url| url.include?("interval=1d") },
           "已修正的窗口内事件月不应重复请求日线"
    prev_row.reload
    assert_equal BigDecimal("10.0"), prev_row.hfq_open, "整行覆盖不得把 hfq 聚合值退回单因子 20"
    assert_equal BigDecimal("20.0"), prev_row.hfq_close, "除权后收盘：10 × 2/1 = 20"
    assert_equal BigDecimal("5.0"), prev_row.qfq_open, "前复权 = 后复权 ÷ hfq_last(2) = 5"
  end

  test "增量模式：库内 hfq 为负的源缺陷遗留事件月被判为未修正，走日线聚合重算自愈" do
    stub_http
    Service.refresh(@stock, mode: :full)

    # 模拟负 adjclose 时代全量重建写入的脏数据：3 月事件月 hfq 列为负
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    march.update_columns(hfq_open: -10.0, hfq_close: -20.0, hfq_high: -22.0, hfq_low: -9.0)

    stub_http
    Service.refresh(@stock, mode: :incremental)

    march.reload
    assert_equal BigDecimal("10.0"), march.hfq_open, "负 hfq 行应重新请求日线修正而非回灌库内负值"
    assert_equal BigDecimal("20.0"), march.hfq_close
    assert_operator march.qfq_close, :>, 0, "前复权列不得由负 hfq 推导"
  end

  # ====================================================
  # 异常与边界
  # ====================================================
  test "404（退市/无数据）返回空结果、不抛异常、不重试、不入库" do
    Service.http_client = build_client("interval=1mo" => nil)

    result = Service.refresh(@stock, mode: :full)

    assert_equal 0, result[:total]
    assert_equal 1, Service.http_client.calls.size, "404 不应触发重试"
    assert_equal 0, @stock.stock_monthly_bars.count
  end

  test "全序列无 adjclose 时整只跳过，不以未复权口径入库" do
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01], adjcloses: [nil, nil, nil]))

    result = Service.refresh(@stock, mode: :full)

    assert_equal 0, result[:total]
    assert_equal 0, @stock.stock_monthly_bars.count
  end

  test "adjclose 缺失的月份沿用上一有效因子（因子分段常数）" do
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01], adjcloses: [5.0, nil, 10.0]))

    Service.refresh(@stock, mode: :full)

    feb = @stock.stock_monthly_bars.find_by(trade_date: FEB)
    assert_equal BigDecimal("2.0"), feb.qfq_factor, "2 月应沿用 1 月的 qf=2 → qfq_factor = 2/1"
    assert_equal BigDecimal("5.0"), feb.qfq_close
  end

  # ====================================================
  # 负 adjclose 源缺陷防御（2026-10 生产事故：SAFE/VHI 等 Yahoo 早期月份 adjclose 整段为负，
  # 负号沿 qf_first/qf 因子链扩散，导致 hfq/qfq 双侧重写为负）
  # ====================================================
  test "负 adjclose 不采信：头部无效段回补首个有效因子，因子链恒为正" do
    # 1-2 月 adjclose 为负（源缺陷段早于首个有效因子，模拟 SAFE 上市初期），3 月起正常
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01 2024-04-01],
                                adjcloses: [-5.0, -5.0, 5.0, 5.0]))

    result = Service.refresh(@stock, mode: :full)

    assert_equal 4, result[:total], "无效月回填后行数不丢（全量重建才能覆盖历史负值行）"
    @stock.stock_monthly_bars.find_each do |row|
      assert_operator row.hfq_factor, :>, 0, "#{row.trade_date} hfq_factor 不得为负"
      assert_operator row.qfq_factor, :>, 0, "#{row.trade_date} qfq_factor 不得为负"
      assert_operator row.hfq_close, :>, 0
      assert_operator row.qfq_close, :>, 0
    end
    jan = @stock.stock_monthly_bars.find_by(trade_date: JAN)
    assert_equal BigDecimal("1.0"), jan.qfq_factor, "头部无效段 qf 回补为首个有效因子 2 → qfq=2/2=1"
    assert_equal BigDecimal("1.0"), jan.hfq_factor, "hfq=2/2=1"
  end

  test "负 adjclose 不采信：中间无效月沿用上一有效因子，且符号翻转不误判为事件月" do
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01], adjcloses: [5.0, -5.0, 5.0]))

    Service.refresh(@stock, mode: :full)

    assert Service.http_client.calls.none? { |url| url.include?("interval=1d") },
           "2 月负比值已被丢弃、沿用 1 月因子，2→-2→2 的符号跳变不应触发日线修正"
    feb = @stock.stock_monthly_bars.find_by(trade_date: FEB)
    assert_equal BigDecimal("1.0"), feb.qfq_factor
    assert_equal BigDecimal("1.0"), feb.hfq_factor
    assert_equal BigDecimal("10.0"), feb.hfq_close
  end

  test "全序列 adjclose 均为负时整只跳过，不以未复权口径入库" do
    stub_http(month: month_body(days: %w[2024-01-01 2024-02-01 2024-03-01], adjcloses: [-5.0, -5.0, -5.0]))

    result = Service.refresh(@stock, mode: :full)

    assert_equal 0, result[:total]
    assert_equal 0, @stock.stock_monthly_bars.count
  end

  private

  def http_calls
    Service.http_client.calls
  end

  # Yahoo v8 chart 响应 fixture：OHLC 与 Sina 版对齐（开=收、高+1、低-1），
  # qf = close ÷ adjclose，默认 [2, 2, 1]（3 月除权一次）。
  # days 为「数据月 1 日」等当地日历日，ts = utc(day) - gmtoffset（还原真实接口的当地时间约定）
  def month_body(days: %w[2024-01-01 2024-02-01 2024-03-01], closes: nil, adjcloses: [5.0, 5.0, 10.0],
                 gmtoffset: HK_GMT_OFFSET)
    closes ||= Array.new(days.size, 10.0)
    {
      "chart" => {
        "result" => [{
          "meta" => { "gmtoffset" => gmtoffset },
          "timestamp" => days.map { |d| Time.utc(*d.split("-").map(&:to_i)).to_i - gmtoffset },
          "indicators" => {
            "quote" => [{
              "open" => closes,
              "high" => closes.map { |c| c + 1.0 },
              "low" => closes.map { |c| c - 1.0 },
              "close" => closes,
              "volume" => closes.each_with_index.map { |_, i| (i + 1) * 1000 }
            }],
            "adjclose" => [{ "adjclose" => adjcloses }]
          }
        }],
        "error" => nil
      }
    }.to_json
  end

  def month_bars_fixture
    [
      { trade_date: JAN, open: BigDecimal("10.0"), high: BigDecimal("11.0"), low: BigDecimal("9.0"), close: BigDecimal("10.0"), volume: 1000, qf: BigDecimal("2.0") },
      { trade_date: FEB, open: BigDecimal("10.0"), high: BigDecimal("11.0"), low: BigDecimal("9.0"), close: BigDecimal("10.0"), volume: 2000, qf: BigDecimal("2.0") },
      { trade_date: MAR, open: BigDecimal("10.0"), high: BigDecimal("11.0"), low: BigDecimal("9.0"), close: BigDecimal("10.0"), volume: 3000, qf: BigDecimal("1.0") }
    ]
  end

  # 2024-03 事件月日线：03-01（除权前 qf=2）与 03-29（除权后 qf=1），OHLC 与月K一致
  # daily 传 "notjson" 可模拟「日线抓取失败」
  def daily_body(first_day = "2024-03-01")
    month_body(days: [first_day, "2024-03-29"], adjcloses: [5.0, 10.0])
  end

  # 月K（interval=1mo）与日线（interval=1d）按 URL 子串路由；nil 模拟 404
  def stub_http(month: nil, daily: :default)
    Service.http_client = build_client(
      "interval=1mo" => month || month_body,
      "interval=1d" => daily == :default ? daily_body : daily
    )
  end

  def build_client(routes)
    client = Object.new
    client.define_singleton_method(:calls) { @calls ||= [] }
    client.define_singleton_method(:get) do |url, *_args|
      calls << url
      body = routes.find { |pattern, _| url.include?(pattern) }&.last
      response = Object.new
      response.define_singleton_method(:success?) { !body.nil? }
      response.define_singleton_method(:status) { body.nil? ? 404 : 200 }
      response.define_singleton_method(:body) { body }
      response
    end
    client
  end
end
