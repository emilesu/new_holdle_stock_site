require "test_helper"

# Yahoo 美股财务指标回退服务：符号转换、原始科目解析、东财口径比率推导
# 口径基准：2026-10-13 用 AAPL 与库内东财 financial_indicators 值逐位实测对齐
class YahooIndicatorServiceTest < ActiveSupport::TestCase
  Service = DataSources::YahooIndicatorService

  setup do
    Service.http_client = nil
  end

  teardown do
    Service.http_client = nil
  end

  # ====================================================
  # 符号转换（与 YahooMonthlyBarService 同规则）
  # ====================================================
  test "yahoo_symbol: 美股点号转连字符、非美股返回 nil" do
    assert_equal "BRK-B", Service.yahoo_symbol(Stock.new(symbol: "BRK.B", market: "US"))
    assert_equal "SOFI", Service.yahoo_symbol(Stock.new(symbol: "sofi", market: "US"))
    assert_nil Service.yahoo_symbol(Stock.new(symbol: "00700.HK", market: "HK"))
    assert_nil Service.yahoo_symbol(Stock.new(symbol: "SH600519", market: "CN"))
  end

  # ====================================================
  # 比率推导（AAPL 2024/2025 两期，数值为 Yahoo 实测原始科目）
  # 库内东财值：2025 年报 roe_avg=171.42 roa=30.93 gross=46.91 net=26.92 current=0.89 quick=0.86 liab=79.48
  # ====================================================
  test "build_indicators: 按东财口径推导比率，平均权益/平均资产用相邻两期均值" do
    series = aapl_series_fixture
    indicators = Service.build_indicators(series)

    assert_equal %w[2024-09 2025-09], indicators.keys.sort
    y2025 = indicators["2025-09"]
    assert_equal BigDecimal("7.49"), y2025[:basic_eps]
    assert_equal BigDecimal("7.46"), y2025[:diluted_eps]
    # 毛利率 = 195.201B / 416.161B * 100 = 46.91（东财 46.91）
    assert_equal BigDecimal("46.91"), y2025[:gross_margin]
    # 净利率 = 112.01B / 416.161B * 100 = 26.92（东财 26.92）
    assert_equal BigDecimal("26.92"), y2025[:net_sales_rate]
    # ROE = 112.01B / ((56.95B + 73.733B)/2) * 100 = 171.40（东财 171.42，舍入差 ≤0.02）
    assert_in_delta 171.42, y2025[:roe_avg].to_f, 0.05
    # ROA = 112.01B / ((364.98B + 359.241B)/2) * 100 = 30.93（东财 30.93）
    assert_in_delta 30.93, y2025[:net_interest_of_ta].to_f, 0.05
    # 流动比率 = 147.96B / 165.63B = 0.89（东财 0.89）
    assert_equal BigDecimal("0.89"), y2025[:current_ratio]
    # 速动比率 = (147.96B - 5.72B) / 165.63B = 0.86（东财 0.86）
    assert_equal BigDecimal("0.86"), y2025[:quick_ratio]
    # 资产负债率 = 285.51B / 359.241B * 100 = 79.48（东财 79.48）
    assert_equal BigDecimal("79.48"), y2025[:asset_liab_ratio]
  end

  test "build_indicators: 最早一期无相邻前值时平均口径退化为期末单点" do
    series = aapl_series_fixture
    indicators = Service.build_indicators(series)

    y2024 = indicators["2024-09"]
    # 首期无前值：ROE = 93.736B / 56.95B * 100 = 164.60（东财用均值口径为 157.41，退化偏差可接受）
    assert_in_delta 164.60, y2024[:roe_avg].to_f, 0.05
    assert_in_delta 25.68, y2024[:net_interest_of_ta].to_f, 0.05
  end

  test "build_indicators: 分母缺失或为零的比率置 nil，整期无值则剔除" do
    series = {
      "annualTotalRevenue" => { "2024-12-31" => BigDecimal("100") },
      "annualBasicEPS" => { "2024-12-31" => BigDecimal("1.5") },
      "annualTotalAssets" => { "2024-12-31" => BigDecimal("0") }
    }
    indicators = Service.build_indicators(series)

    y2024 = indicators["2024-12"]
    assert_equal BigDecimal("1.5"), y2024[:basic_eps]
    assert_nil y2024[:gross_margin], "毛利缺失应为 nil"
    refute y2024.key?(:net_interest_of_ta), "总资产为 0，ROA 应被 compact 剔除"

    empty = Service.build_indicators({})
    assert_empty empty
  end

  test "build_indicators: 归母净利缺失时回退 annualNetIncome" do
    series = {
      "annualTotalRevenue" => { "2024-12-31" => BigDecimal("1000") },
      "annualNetIncome" => { "2024-12-31" => BigDecimal("120") },
      "annualStockholdersEquity" => { "2024-12-31" => BigDecimal("1000") }
    }
    indicators = Service.build_indicators(series)

    assert_equal BigDecimal("12.0"), indicators["2024-12"][:net_sales_rate]
    assert_equal BigDecimal("12.0"), indicators["2024-12"][:roe_avg]
  end

  # ====================================================
  # fetch_annual（stub HTTP，验证端到端返回与异常兜底）
  # ====================================================
  test "fetch_annual: 解析 Yahoo timeseries 并按 YYYY-MM 键返回" do
    stock = Stock.new(symbol: "SOFI", market: "US")
    Service.http_client = build_client("annualBasicEPS" => timeseries_body)

    indicators = Service.fetch_annual(stock)
    assert_equal %w[2024-12 2025-12], indicators.keys.sort
    assert_equal BigDecimal("0.46"), indicators["2024-12"][:basic_eps]
  end

  test "fetch_annual: 非美股或接口无数据返回空哈希" do
    assert_empty Service.fetch_annual(Stock.new(symbol: "600519.SS", market: "CN"))

    stock = Stock.new(symbol: "GONE", market: "US")
    Service.http_client = build_client("annualBasicEPS" => '{"timeseries":{"result":[]}}')
    assert_empty Service.fetch_annual(stock)
  end

  test "fetch_annual: rows 含 nil/非 Hash 元素时跳过不抛异常" do
    stock = Stock.new(symbol: "WEIRD", market: "US")
    body = { timeseries: { result: [
      { meta: { type: ["annualBasicEPS"] }, annualBasicEPS: [
        nil, "junk", { asOfDate: "2025-12-31", reportedValue: { raw: 1.1 } }
      ] }
    ] } }.to_json
    Service.http_client = build_client("annualBasicEPS" => body)

    indicators = Service.fetch_annual(stock)
    assert_equal BigDecimal("1.1"), indicators["2025-12"][:basic_eps]
  end

  # ====================================================
  # fixtures
  # ====================================================

  # AAPL 2024/2025 财年原始科目（Yahoo 实测值，单位：元）
  def aapl_series_fixture
    {
      "annualBasicEPS" => { "2024-09-30" => BigDecimal("6.11"), "2025-09-30" => BigDecimal("7.49") },
      "annualDilutedEPS" => { "2024-09-30" => BigDecimal("6.08"), "2025-09-30" => BigDecimal("7.46") },
      "annualTotalRevenue" => { "2024-09-30" => BigDecimal("391035000000"), "2025-09-30" => BigDecimal("416161000000") },
      "annualNetIncomeCommonStockholders" => { "2024-09-30" => BigDecimal("93736000000"), "2025-09-30" => BigDecimal("112010000000") },
      "annualGrossProfit" => { "2024-09-30" => BigDecimal("180683000000"), "2025-09-30" => BigDecimal("195201000000") },
      "annualTotalAssets" => { "2024-09-30" => BigDecimal("364980000000"), "2025-09-30" => BigDecimal("359241000000") },
      "annualTotalLiabilitiesNetMinorityInterest" => { "2025-09-30" => BigDecimal("285510000000") },
      "annualStockholdersEquity" => { "2024-09-30" => BigDecimal("56950000000"), "2025-09-30" => BigDecimal("73733000000") },
      "annualCurrentAssets" => { "2025-09-30" => BigDecimal("147960000000") },
      "annualCurrentLiabilities" => { "2025-09-30" => BigDecimal("165630000000") },
      "annualInventory" => { "2025-09-30" => BigDecimal("5720000000") }
    }
  end

  def timeseries_body
    {
      timeseries: {
        result: [
          { meta: { type: ["annualBasicEPS"] },
            annualBasicEPS: [
              { asOfDate: "2024-12-31", reportedValue: { raw: 0.46 } },
              { asOfDate: "2025-12-31", reportedValue: { raw: 1.1 } }
            ] },
          { meta: { type: ["annualTotalRevenue"] },
            annualTotalRevenue: [
              { asOfDate: "2024-12-31", reportedValue: { raw: 2612342000 } },
              { asOfDate: "2025-12-31", reportedValue: { raw: 3320000000 } }
            ] }
        ]
      }
    }.to_json
  end

  def build_client(routes)
    client = Object.new
    client.define_singleton_method(:get) do |url, *_args|
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
