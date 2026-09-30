require "test_helper"

# 月K抓取服务：复权换算方向、常数不变量、增量重算策略
class SinaMonthlyBarServiceTest < ActiveSupport::TestCase
  Service = DataSources::SinaMonthlyBarService
  FactorService = DataSources::SinaAdjFactorService

  JAN = Date.new(2024, 1, 31)
  FEB = Date.new(2024, 2, 29)
  MAR = Date.new(2024, 3, 29)

  setup do
    @stock = Stock.create!(symbol: "SH999999", name: "月K测试", market: "CN")
    Service.http_client = nil
    FactorService.http_client = nil
  end

  teardown do
    Service.http_client = nil
    FactorService.http_client = nil
  end

  # ====================================================
  # 复权换算方向（Task 0 探针结论的正向断言）
  # ====================================================
  test "前复权价 = 不复权价 ÷ qfq_factor" do
    bars = Service.build_bars(@stock, raw_bars, qfq_factors, hfq_factors)

    # 10.000 ÷ 2.0 = 5.0（首期哨兵因子）
    assert_equal BigDecimal("5.0"), bars[0][:qfq_open]
    # 10.000 ÷ 1.0 = 10.0（3 月除权事件在当月生效）
    assert_equal BigDecimal("10.0"), bars[2][:qfq_close]
  end

  test "后复权价 = 不复权价 × hfq_factor" do
    bars = Service.build_bars(@stock, raw_bars, qfq_factors, hfq_factors)

    assert_equal BigDecimal("10.0"), bars[0][:hfq_close]
    assert_equal BigDecimal("20.0"), bars[2][:hfq_close]
  end

  test "因子取用规则：事件日 <= 该月最后交易日，当月即生效" do
    events = [
      { date: Date.new(1900, 1, 1), factor: BigDecimal("1.0") },
      { date: Date.new(2024, 3, 15), factor: BigDecimal("2.0") }
    ]

    bars = Service.build_bars(@stock, raw_bars, events, events)

    assert_equal BigDecimal("1.0"), bars[0][:hfq_factor], "1 月不应命中 3 月的因子事件"
    assert_equal BigDecimal("1.0"), bars[1][:hfq_factor], "2 月不应命中 3 月的因子事件"
    assert_equal BigDecimal("2.0"), bars[2][:hfq_factor], "3 月最后交易日 03-29 >= 03-15，当月生效"
  end

  test "因子事件日落在该月最后交易日之后时不生效" do
    events = [
      { date: Date.new(1900, 1, 1), factor: BigDecimal("1.0") },
      { date: Date.new(2024, 3, 30), factor: BigDecimal("2.0") }
    ]

    bars = Service.build_bars(@stock, raw_bars, events, events)

    assert_equal BigDecimal("1.0"), bars[2][:hfq_factor], "03-30 晚于 3 月最后交易日 03-29，应下月生效"
  end

  test "两套复权的一致性不变量：后复权价 ÷ 前复权价 恒等于 hfq_last" do
    bars = Service.build_bars(@stock, raw_bars, qfq_factors, hfq_factors)

    ratios = bars.map { |bar| bar[:hfq_close] / bar[:qfq_close] }
    assert ratios.uniq.size == 1, "所有月份的比值应当相同，实际：#{ratios.uniq.inspect}"
    assert_equal BigDecimal("2.0"), ratios.first
  end

  test "后复权价可精确反推不复权价" do
    bars = Service.build_bars(@stock, raw_bars, qfq_factors, hfq_factors)

    bars.each do |bar|
      assert_equal bar[:close], (bar[:hfq_close] / bar[:hfq_factor]).round(4)
    end
  end

  # ====================================================
  # 落库与重算策略
  # ====================================================
  test "全量 refresh 落库 3 根月K" do
    stub_http

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, result[:total]
    assert_equal 3, @stock.stock_monthly_bars.count
    assert_equal [JAN, FEB, Date.new(2024, 3, 29)], @stock.stock_monthly_bars.order(:trade_date).pluck(:trade_date)
  end

  test "全量模式覆盖所有列" do
    stub_http
    Service.refresh(@stock, mode: :full)

    # 第二次抓取：两套因子整体变化，全量模式下历史行应被完全覆盖
    stub_http(hfq_events: [{ "d" => "1900-01-01", "f" => "3.0" }], qfq_events: [{ "d" => "1900-01-01", "f" => "4.0" }])
    Service.refresh(@stock, mode: :full)

    jan = @stock.stock_monthly_bars.find_by(trade_date: JAN)
    assert_equal BigDecimal("30.0"), jan.hfq_close
    assert_equal BigDecimal("2.5"), jan.qfq_close
  end

  test "增量模式：历史后复权列不被覆盖，前复权列整段重写" do
    stub_http
    Service.refresh(@stock, mode: :full)

    jan = @stock.stock_monthly_bars.find_by(trade_date: JAN)
    assert_equal BigDecimal("10.0"), jan.hfq_close
    assert_equal BigDecimal("5.0"), jan.qfq_close

    # 后复权哨兵因子被人为抬高（真实数据中「只增不改」不会出现，此处用于证明增量不覆盖历史后复权列）
    stub_http(hfq_events: [{ "d" => "1900-01-01", "f" => "3.0" }], qfq_events: [{ "d" => "1900-01-01", "f" => "4.0" }])
    Service.refresh(@stock, mode: :incremental)

    jan.reload
    assert_equal BigDecimal("10.0"), jan.hfq_close, "增量模式下历史后复权列不应被覆盖"
    assert_equal BigDecimal("2.5"), jan.qfq_close, "增量模式下前复权列应整段重写"
  end

  # ====================================================
  # 除权事件月修正（2026-09-30 修复「月中除权」失真）
  # ====================================================
  test "全量模式：除权日落在月中时，事件月按逐日因子聚合而非月末单一因子" do
    stub_http
    Service.refresh(@stock, mode: :full)

    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    # 03-01 开盘在除权日 03-15 之前：前复权 = 10 ÷ 2（旧因子），月末单一因子会错算成 10 ÷ 1
    assert_equal BigDecimal("5.0"), march.qfq_open
    # 复权后 high = max(11÷2, 11÷1) = 11；low = min(9÷2, 9÷1) = 4.5
    assert_equal BigDecimal("11.0"), march.qfq_high
    assert_equal BigDecimal("4.5"), march.qfq_low
    # 收盘在除权之后：与单因子结果一致
    assert_equal BigDecimal("10.0"), march.qfq_close
    # 后复权同样失真同样修：open = 10 × 1（旧因子），而非 10 × 2
    assert_equal BigDecimal("10.0"), march.hfq_open
    assert_equal BigDecimal("22.0"), march.hfq_high
    assert_equal BigDecimal("9.0"), march.hfq_low
    assert_equal BigDecimal("20.0"), march.hfq_close
    # 常数不变量仍成立：hfq_close ÷ qfq_close == hfq_last(2)
    assert_equal BigDecimal("2.0"), march.hfq_close / march.qfq_close
  end

  test "全量模式：非事件月不受影响，仍按单一因子换算" do
    stub_http
    Service.refresh(@stock, mode: :full)

    jan = @stock.stock_monthly_bars.find_by(trade_date: JAN)
    assert_equal BigDecimal("5.0"), jan.qfq_open   # 10 ÷ 2
    assert_equal BigDecimal("10.0"), jan.hfq_open  # 10 × 1
  end

  test "增量模式：已修正的历史事件月按 前复权=后复权÷hfq_last 推导，不再请求该月日线" do
    four = %w[2024-01-31 2024-02-29 2024-03-29 2024-04-30]
    stub_http(raw_body: raw_bars_body_for(four))
    Service.refresh(@stock, mode: :full)
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("10.0"), march.hfq_open, "全量修正后 hfq_open = 10 × 旧因子1"

    # 4 月新发生除权（04-20）：hfq_last 2 → 4；3 月是「已修正的历史事件月」且非当月进行中
    stub_http(
      raw_body: raw_bars_body_for(four),
      hfq_events: [{ "d" => "1900-01-01", "f" => "1.0" }, { "d" => "2024-03-15", "f" => "2.0" }, { "d" => "2024-04-20", "f" => "4.0" }],
      qfq_events: [{ "d" => "1900-01-01", "f" => "4.0" }, { "d" => "2024-03-15", "f" => "2.0" }, { "d" => "2024-04-20", "f" => "1.0" }]
    )
    Service.refresh(@stock, mode: :incremental)

    march.reload
    assert_equal BigDecimal("10.0"), march.hfq_open, "已修正的历史后复权列保持只增不改"
    # 前复权 = 后复权 ÷ 新 hfq_last：10 ÷ 4 = 2.5；单因子旧算法会错算成 10 ÷ 2 = 5
    assert_equal BigDecimal("2.5"), march.qfq_open
    assert_equal BigDecimal("5.0"), march.qfq_close
  end

  test "增量模式：存量旧算法（单因子）事件月行被识别并重新修正" do
    four = %w[2024-01-31 2024-02-29 2024-03-29 2024-04-30]
    stub_http(raw_body: raw_bars_body_for(four))
    Service.refresh(@stock, mode: :full)

    # 人为把 3 月行改回旧单因子算法值（hfq_open = 10 × 月末因子2 = 20），模拟修复前入库的存量数据
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    march.update!(hfq_open: BigDecimal("20.0"), qfq_open: BigDecimal("10.0"))

    Service.refresh(@stock, mode: :incremental)

    march.reload
    assert_equal BigDecimal("10.0"), march.hfq_open, "旧算法行应被识别并修正回 10 × 旧因子1"
    assert_equal BigDecimal("5.0"), march.qfq_open, "前复权应修正回 10 ÷ 旧因子2"
  end

  test "日线抓取失败时事件月降级为单因子落库，不中断本只股票" do
    stub_http(daily_body: nil)

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, result[:total]
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("10.0"), march.qfq_open, "降级时保持单因子换算值"
    assert_equal BigDecimal("20.0"), march.hfq_open
  end

  test "日线历史截断覆盖不住事件月时，本轮跳过修正、按单因子落库" do
    # 日线起点 03-05 晚于事件月月初 03-01，且 3 月并非该股最早月份（1 月起有月K）→ 判定截断
    stub_http(daily_body: sina_daily_body("2024-03-05"))

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, result[:total]
    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("10.0"), march.qfq_open, "跳过修正时保持单因子换算值"
    assert_equal BigDecimal("20.0"), march.hfq_open
  end

  test "事件月为上市首月时，日线自月半起属正常，不误判为截断" do
    # 只有 3 月一根月K（上市首月即事件月），日线从 03-05 起 = 上市日晚于月初，属正常
    stub_http(raw_body: raw_bars_body_for(["2024-03-29"]), daily_body: sina_daily_body("2024-03-05"))

    Service.refresh(@stock, mode: :full)

    march = @stock.stock_monthly_bars.find_by(trade_date: MAR)
    assert_equal BigDecimal("5.0"), march.qfq_open, "首月事件月应正常修正：10 ÷ 除权前因子2"
    assert_equal BigDecimal("10.0"), march.hfq_open
  end

  test "当月交易日推进时清理同月旧行，不留下重复月份" do
    stub_http(raw_body: raw_bars_body("2024-03-15"))
    Service.refresh(@stock, mode: :full)
    assert_equal Date.new(2024, 3, 15), @stock.stock_monthly_bars.maximum(:trade_date)

    stub_http(raw_body: raw_bars_body("2024-03-29"))
    Service.refresh(@stock, mode: :full)

    march_dates = @stock.stock_monthly_bars
      .where(trade_date: Date.new(2024, 3, 1)..Date.new(2024, 3, 31))
      .pluck(:trade_date)
    assert_equal [Date.new(2024, 3, 29)], march_dates
    assert_equal 3, @stock.stock_monthly_bars.count
  end

  test "跨月时清理上月残留的部分月行，不留下同月重复" do
    # 3 月未走完时抓一次：新浪以「当前最新交易日」03-15 为日期
    stub_http(raw_body: raw_bars_body_for(%w[2024-01-31 2024-02-29 2024-03-15]))
    Service.refresh(@stock, mode: :full)
    assert_equal Date.new(2024, 3, 15), @stock.stock_monthly_bars.maximum(:trade_date)

    # 次月再抓：这次才拿到 3 月真实的月末行 03-29，02-15 那类残留行必须被清掉
    stub_http(raw_body: raw_bars_body_for(%w[2024-01-31 2024-02-29 2024-03-29 2024-04-01]))
    Service.refresh(@stock, mode: :full)

    march_dates = @stock.stock_monthly_bars
      .where(trade_date: Date.new(2024, 3, 1)..Date.new(2024, 3, 31))
      .pluck(:trade_date)
    assert_equal [Date.new(2024, 3, 29)], march_dates, "3 月应只剩真实月末行，不得残留 03-15"
    assert_equal 4, @stock.stock_monthly_bars.count
  end

  test "因子抓取失败时不落库，且 HTTP 非 2xx 会重试 RETRY_TIMES 次" do
    Service.http_client = build_client("getKLineData" => raw_bars_body)
    factor_client = build_client("/qfq.js" => nil, "/hfq.js" => factor_body("hfq", default_hfq_events))
    FactorService.http_client = factor_client

    result = Service.refresh(@stock, mode: :full)

    assert_equal 3, factor_client.calls.count { |url| url.include?("/qfq.js") },
                 "首次请求 + RETRY_TIMES(2) 次重试 = 3 次"
    assert_equal 0, result[:total], "因子缺失应跳过本只"
    assert_equal 0, @stock.stock_monthly_bars.count, "不得以不复权口径写入错误数据"
  end

  test "无月K数据时返回空结果且不写入" do
    Service.http_client = build_client("getKLineData" => "[]")

    result = Service.refresh(@stock, mode: :full)

    assert_equal 0, result[:total]
    assert_equal 0, @stock.stock_monthly_bars.count
  end

  # ====================================================
  # 因子解析
  # ====================================================
  test "因子文件解析并按日期升序，库内 SH 代码转为小写新浪代码" do
    assert_equal "sh600519", FactorService.sina_code("SH600519")

    FactorService.http_client = build_client(
      "/qfq.js" => "var sh600519qfq={\"total\":2,\"data\":[{\"d\":\"2024-03-15\", \"f\":\"1.0000\"},{\"d\":\"1900-01-01\", \"f\":\"2.0000\"}]}"
    )

    factors = FactorService.fetch_qfq("SH600519")

    assert_equal [Date.new(1900, 1, 1), Date.new(2024, 3, 15)], factors.map { |row| row[:date] }
    assert_equal BigDecimal("2.0000"), factors.first[:factor]
  end

  private

  def raw_bars
    JSON.parse(raw_bars_body)
  end

  def raw_bars_body(march_day = "2024-03-29")
    raw_bars_body_for(["2024-01-31", "2024-02-29", march_day])
  end

  def raw_bars_body_for(days)
    days.each_with_index.map do |day, index|
      { "day" => day, "open" => "10.000", "high" => "11.000", "low" => "9.000",
        "close" => "10.000", "volume" => ((index + 1) * 1000).to_s }
    end.to_json
  end

  # 3 月除权一次：后复权因子 1 → 2，前复权因子 2 → 1
  def hfq_factors
    [
      { date: Date.new(1900, 1, 1), factor: BigDecimal("1.0") },
      { date: Date.new(2024, 3, 15), factor: BigDecimal("2.0") }
    ]
  end

  def qfq_factors
    [
      { date: Date.new(1900, 1, 1), factor: BigDecimal("2.0") },
      { date: Date.new(2024, 3, 15), factor: BigDecimal("1.0") }
    ]
  end

  # 月K（scale=7200）与日线（scale=240）同源同域，按 scale 参数路由；
  # daily_body 传 nil 可模拟「日线抓取失败」
  def stub_http(raw_body: nil, hfq_events: nil, qfq_events: nil, daily_body: :default)
    Service.http_client = build_client(
      "scale=7200" => raw_body || raw_bars_body,
      "scale=240" => daily_body == :default ? sina_daily_body : daily_body
    )
    FactorService.http_client = build_client(
      "/qfq.js" => factor_body("qfq", qfq_events || default_qfq_events),
      "/hfq.js" => factor_body("hfq", hfq_events || default_hfq_events)
    )
  end

  # 2024-03 事件月日线：03-15 除权（hfq 1→2，qfq 2→1）
  #   两日 OHLC 与月K fixture（开10 高11 低9 收10）保持一致
  #   first_day 可后移以模拟「日线历史被截断」
  def sina_daily_body(first_day = "2024-03-01")
    rows = [
      { "day" => first_day, "open" => "10.000", "high" => "11.000", "low" => "9.000", "close" => "10.000", "volume" => "100" },
      { "day" => "2024-03-29", "open" => "10.000", "high" => "11.000", "low" => "9.000", "close" => "10.000", "volume" => "100" }
    ]
    JSON.generate(rows)
  end

  def default_hfq_events
    [{ "d" => "1900-01-01", "f" => "1.0" }, { "d" => "2024-03-15", "f" => "2.0" }]
  end

  def default_qfq_events
    [{ "d" => "1900-01-01", "f" => "2.0" }, { "d" => "2024-03-15", "f" => "1.0" }]
  end

  def factor_body(kind, events)
    "var sh999999#{kind}=#{JSON.generate('total' => events.size, 'data' => events)}"
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