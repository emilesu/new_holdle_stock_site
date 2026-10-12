require "test_helper"

# F10 补充抓取：扣非归母净利/扣非加权ROE/披露日期/稀释EPS 回填与跳过逻辑
class CnFetcherF10SupplementTest < ActiveSupport::TestCase
  setup do
    @stock = Stock.create!(symbol: "SH603259", name: "药明康德", market: "CN", status: "active")
    @report_date = Date.new(2025, 12, 31)
    fr = FinancialReport.create!(stock: @stock, report_date: @report_date, report_type: "CN_ANNUAL",
                                 market: "CN", period_type: "annual", currency: "CNY")
    @indicator = FinancialIndicator.create!(financial_report: fr, stock: @stock,
                                            report_date: @report_date, market: "CN", period_type: "annual")
  end

  # 用桩替换 http_get，返回固定 F10 payload
  def fetcher_with_payload(payload)
    fetcher = DataSources::Fetchers::CnFetcher.new
    fetcher.define_singleton_method(:http_get) { |_url, **_kwargs| payload }
    fetcher
  end

  test "回填扣非/披露日期字段，库内不存在的期次跳过" do
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2026-03-23 00:00:00",
        "KCFJCXSYJLR" => 13_240_556_954.42, "ROEKCJQ" => 19.74, "EPSXS" => 6.55 },
      { "REPORT_DATE" => "2024-12-31 00:00:00", "NOTICE_DATE" => "2025-03-18 00:00:00",
        "KCFJCXSYJLR" => 9_999.0, "ROEKCJQ" => 15.0, "EPSXS" => 5.0 }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, @stock, "603259.SH", "CN")

    assert_equal :success, result[:status]
    assert_equal 1, result[:count]
    @indicator.reload
    assert_equal BigDecimal("13240556954.42"), @indicator.deducted_net_profit
    assert_equal BigDecimal("19.74"), @indicator.deducted_roe_weighted
    assert_equal BigDecimal("6.55"), @indicator.eps_diluted
    assert_equal Date.new(2026, 3, 23), @indicator.disclosed_at
  end

  test "字段值无变化时跳过更新" do
    @indicator.update!(deducted_net_profit: 100.0, deducted_roe_weighted: 10.0,
                       eps_diluted: 1.0, disclosed_at: Date.new(2026, 3, 23))
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2026-03-23 00:00:00",
        "KCFJCXSYJLR" => 100.0, "ROEKCJQ" => 10.0, "EPSXS" => 1.0 }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, @stock, "603259.SH", "CN")
    assert_equal :skipped, result[:status]
  end

  test "接口无数据返回 failed 且不影响库内记录" do
    result = fetcher_with_payload(nil).send(:fetch_f10_supplement, @stock, "603259.SH", "CN")

    assert_equal :failed, result[:status]
    @indicator.reload
    assert_nil @indicator.deducted_net_profit
  end

  test "NOTICE_DATE 为空时披露日期不写入" do
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => nil,
        "KCFJCXSYJLR" => 1000.0, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, @stock, "603259.SH", "CN")
    assert_equal :success, result[:status]
    @indicator.reload
    assert_equal BigDecimal("1000.0"), @indicator.deducted_net_profit
    assert_nil @indicator.disclosed_at
  end
end
