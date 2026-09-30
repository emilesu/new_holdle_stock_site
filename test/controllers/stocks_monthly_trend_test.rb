require "test_helper"

# 股票详情页月K三联图接口：区间切片、复权切换、MACD 预热、月ROE 阶梯
class StocksMonthlyTrendTest < ActionDispatch::IntegrationTest
  MACD_FAST = 12
  MACD_SLOW = 26
  MACD_SIGNAL = 9

  setup do
    @stock = Stock.create!(symbol: "SH888888", name: "月K接口测试", market: "CN")
  end

  test "无月K数据时返回 200 与空数组" do
    get monthly_trend_stock_path(@stock, format: :json)

    assert_response :success
    body = response.parsed_body
    assert body["success"]
    assert_equal [], body["bars"]
    assert_equal [], body["macd"]
    assert_equal [], body["roe"]
    assert_equal "qfq", body["adj"]
    assert_equal "10y", body["range"]
    assert_equal 0, body["meta"]["total_bars"]
  end

  test "默认近10年返回 120 根，bars/macd/roe 等长" do
    create_bars(150)
    get monthly_trend_stock_path(@stock, format: :json)

    body = response.parsed_body
    assert_equal 150, body["meta"]["total_bars"]
    assert_equal 120, body["bars"].size
    assert_equal 120, body["macd"].size
    assert_equal 120, body["roe"].size
    assert_equal 30, body["meta"]["warmup_bars"]
    assert_equal "qfq", body["meta"]["adj"]
  end

  test "range=all 返回全量历史" do
    create_bars(150)
    get monthly_trend_stock_path(@stock, format: :json), params: { range: "all" }

    body = response.parsed_body
    assert_equal 150, body["bars"].size
    assert_equal 0, body["meta"]["warmup_bars"]
    assert_equal "all", body["range"]
  end

  test "非法参数回落默认值" do
    create_bars(5)
    get monthly_trend_stock_path(@stock, format: :json), params: { range: "1d", adj: "none" }

    body = response.parsed_body
    assert_equal "10y", body["range"]
    assert_equal "qfq", body["adj"]
  end

  test "两个 range 的 MACD 末值一致（全历史递推后再切片）" do
    create_bars(150)

    get monthly_trend_stock_path(@stock, format: :json), params: { range: "10y" }
    ten_year = response.parsed_body["macd"].last
    get monthly_trend_stock_path(@stock, format: :json), params: { range: "all" }
    full = response.parsed_body["macd"].last

    assert_in_delta full["dif"], ten_year["dif"], 1e-9
    assert_in_delta full["dea"], ten_year["dea"], 1e-9
    assert_in_delta full["hist"], ten_year["hist"], 1e-9
  end

  test "adj=qfq 的 MACD 等于直接对前复权收盘价递推（EMA 常数倍缩放等价）" do
    create_bars(150)
    get monthly_trend_stock_path(@stock, format: :json), params: { range: "all", adj: "qfq" }

    last = response.parsed_body["macd"].last
    closes = StockMonthlyBar.where(stock_id: @stock.id).order(:trade_date).pluck(:qfq_close).map(&:to_f)
    dif, dea, hist = macd_series(closes)

    # 接口数值按 6 位小数输出，容差取 1e-5
    assert_in_delta dif.last, last["dif"], 1e-5
    assert_in_delta dea.last, last["dea"], 1e-5
    assert_in_delta hist.last, last["hist"], 1e-5
  end

  test "切换复权：bars 逐点比值恒为常数，roe 完全一致" do
    create_bars(150)
    get monthly_trend_stock_path(@stock, format: :json), params: { adj: "qfq" }
    qfq_body = response.parsed_body
    get monthly_trend_stock_path(@stock, format: :json), params: { adj: "hfq" }
    hfq_body = response.parsed_body

    ratios = hfq_body["bars"].zip(qfq_body["bars"]).map { |hfq_bar, qfq_bar| hfq_bar["c"] / qfq_bar["c"] }
    assert_equal 120, ratios.size
    assert ratios.all? { |ratio| (ratio - 2.0).abs < 1e-6 }, "前后复权比值应为常数 2.0，实际：#{ratios.uniq.inspect}"

    assert_equal qfq_body["roe"], hfq_body["roe"]
    assert_equal "hfq", hfq_body["adj"]
  end

  test "月ROE 阶梯：生效月为报告期 + 4 个月，之前留空" do
    create_roe_bars
    create_annual_indicator(Date.new(2021, 12, 31), 15.0)
    create_annual_indicator(Date.new(2022, 12, 31), 18.0)
    create_annual_indicator(Date.new(2023, 12, 31), 25.0)

    get monthly_trend_stock_path(@stock, format: :json), params: { range: "all" }

    roe = response.parsed_body["roe"].index_by { |item| item["t"] }
    # 首期年报（2021-12-31 + 4 个月 = 2022-04）生效前留空
    assert_nil roe["2021-06-30"]["value"]
    # 2024-03 生效的仍是 2022 年报
    assert_equal 18.0, roe["2024-03-29"]["value"]
    assert_equal "2022-12-31", roe["2024-03-29"]["report_date"]
    # 2023-12-31 + 4 个月 = 2024-04，当月即生效
    assert_equal 25.0, roe["2024-04-30"]["value"]
    assert_equal "2023-12-31", roe["2024-04-30"]["report_date"]
  end

  private

  def create_bars(count, start_date: Date.new(2012, 1, 31))
    rows = []
    date = start_date
    count.times do |index|
      rows << price_row(date, 10.0 + (index % 7))
      date = (date >> 1).end_of_month
    end
    StockMonthlyBar.insert_all(rows)
  end

  def create_roe_bars
    StockMonthlyBar.insert_all([
      price_row(Date.new(2021, 6, 30), 8.0),
      price_row(Date.new(2024, 3, 29), 9.0),
      price_row(Date.new(2024, 4, 30), 11.0)
    ])
  end

  # 后复权因子恒为 2、前复权因子恒为 1 ⇒ 后复权序列 = 前复权序列 × 2（常数倍，便于校验缩放等价性）
  def price_row(trade_date, close)
    now = Time.current
    {
      stock_id: @stock.id,
      market: "CN",
      trade_date: trade_date,
      open: close,
      close: close,
      high: close + 1,
      low: close - 1,
      volume: 1000,
      qfq_open: close,
      qfq_close: close,
      qfq_high: close + 1,
      qfq_low: close - 1,
      qfq_factor: 1.0,
      hfq_open: close * 2,
      hfq_close: close * 2,
      hfq_high: (close + 1) * 2,
      hfq_low: (close - 1) * 2,
      hfq_factor: 2.0,
      created_at: now,
      updated_at: now
    }
  end

  def create_annual_indicator(report_date, roe_avg)
    report = FinancialReport.create!(
      stock: @stock, market: "CN", report_date: report_date, report_type: "年度", period_type: "annual"
    )
    FinancialIndicator.create!(
      stock: @stock, financial_report: report, market: "CN",
      report_date: report_date, period_type: "annual", roe_avg: roe_avg
    )
  end

  def macd_series(closes)
    fast = ema(closes, MACD_FAST)
    slow = ema(closes, MACD_SLOW)
    dif = fast.each_with_index.map { |value, index| value - slow[index] }
    dea = ema(dif, MACD_SIGNAL)
    [dif, dea, dif.each_with_index.map { |value, index| 2 * (value - dea[index]) }]
  end

  def ema(values, period)
    alpha = 2.0 / (period + 1)
    previous = nil
    values.map do |value|
      previous = previous.nil? ? value.to_f : alpha * value.to_f + (1 - alpha) * previous
    end
  end
end