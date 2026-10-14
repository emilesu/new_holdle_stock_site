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

  # 回归：源端某轮对已回填字段返回 null、另一字段同时有变化时，
  # 变更检测虽排除 nil，写入也必须跳过 nil，不得抹掉已回填值
  test "已回填字段本轮返回 null 时保留原值，仅更新有变化的非 nil 字段" do
    @indicator.update!(deducted_net_profit: 100.0, disclosed_at: Date.new(2026, 3, 23))
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => nil,
        "KCFJCXSYJLR" => 200.0, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, @stock, "603259.SH", "CN")

    assert_equal :success, result[:status]
    @indicator.reload
    assert_equal BigDecimal("200.0"), @indicator.deducted_net_profit
    assert_equal Date.new(2026, 3, 23), @indicator.disclosed_at
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

  # ── 披露日语义校验门（2026-10-14 呆头儿报告：北交所 F10 NOTICE_DATE 不可靠）──

  # 北交所场景：F10 返回业绩快报式日期（窗口内但错误），公告接口返回真实年报公告日
  def bj_stock_with_indicator
    stock = Stock.create!(symbol: "BJ920206", name: "彩客科技", market: "CN",
                          status: "active", listing_date: Date.new(2025-11-20))
    report_date = Date.new(2025, 12, 31)
    fr = FinancialReport.create!(stock: stock, report_date: report_date, report_type: "CN_ANNUAL",
                                 market: "CN", period_type: "annual", currency: "CNY")
    indicator = FinancialIndicator.create!(financial_report: fr, stock: stock,
                                           report_date: report_date, market: "CN", period_type: "annual")
    [stock, indicator]
  end

  # 按 URL 分发桩响应：datacenter=F10 payload，np-anotice=公告列表
  def fetcher_with_routes(f10_payload, ann_payload)
    fetcher = DataSources::Fetchers::CnFetcher.new
    fetcher.define_singleton_method(:http_get) do |url, **_kwargs|
      url.to_s.include?("np-anotice") ? ann_payload : f10_payload
    end
    fetcher
  end

  test "北交所年报披露日以公告接口为准，不采信 F10 错误日期" do
    stock, indicator = bj_stock_with_indicator
    f10 = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2026-02-25 00:00:00",
        "KCFJCXSYJLR" => 100.0, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }
    ann = { "data" => { "list" => [
      { "title" => "彩客科技:2026年半年度报告", "notice_date" => "2026-08-18 00:00:00" },
      { "title" => "彩客科技:独立董事关于2025年年度报告编制的提示性公告", "notice_date" => "2026-01-22 00:00:00" },
      { "title" => "彩客科技:2025年年度报告摘要", "notice_date" => "2026-03-18 00:00:00" },
      { "title" => "彩客科技:2025年年度报告", "notice_date" => "2026-03-18 00:00:00" }
    ] } }

    result = fetcher_with_routes(f10, ann).send(:fetch_f10_supplement, stock, "920206.BJ", "CN")

    assert_equal :success, result[:status]
    indicator.reload
    assert_equal Date.new(2026, 3, 18), indicator.disclosed_at
    assert_equal BigDecimal("100.0"), indicator.deducted_net_profit
  end

  test "北交所年报公告接口查不到时披露日留空，不写入 F10 可疑值" do
    stock, indicator = bj_stock_with_indicator
    indicator.update!(disclosed_at: Date.new(2026, 3, 18))
    f10 = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2026-02-25 00:00:00",
        "KCFJCXSYJLR" => nil, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }
    ann = { "data" => { "list" => [
      { "title" => "彩客科技:关于变更证券事务代表的公告", "notice_date" => "2026-05-06 00:00:00" }
    ] } }

    result = fetcher_with_routes(f10, ann).send(:fetch_f10_supplement, stock, "920206.BJ", "CN")

    assert_equal :skipped, result[:status]
    indicator.reload
    assert_equal Date.new(2026, 3, 18), indicator.disclosed_at
  end

  test "F10 日期超出期次披露窗口时不写入（批量回填场景）" do
    stock = Stock.create!(symbol: "SH600001", name: "测试沪股", market: "CN", status: "active")
    report_date = Date.new(2023, 12, 31)
    fr = FinancialReport.create!(stock: stock, report_date: report_date, report_type: "CN_ANNUAL",
                                 market: "CN", period_type: "annual", currency: "CNY")
    indicator = FinancialIndicator.create!(financial_report: fr, stock: stock,
                                           report_date: report_date, market: "CN", period_type: "annual")
    # 2023 年报的披露窗口为 2024-01-01..2024-06-30，2024-09-27 为上市备案批量回填日期
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2023-12-31 00:00:00", "NOTICE_DATE" => "2024-09-27 00:00:00",
        "KCFJCXSYJLR" => 500.0, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, stock, "600001.SH", "CN")

    assert_equal 1, result[:gated]
    indicator.reload
    assert_nil indicator.disclosed_at
    assert_equal BigDecimal("500.0"), indicator.deducted_net_profit
  end

  # 次新股/转板股上市前的招股书或新三板期披露日合法（早于上市日），豁免窗口校验、正常写入
  test "次新股上市前披露日豁免窗口校验并写入" do
    stock = Stock.create!(symbol: "SZ301602", name: "测试深股", market: "CN",
                          status: "active", listing_date: Date.new(2026, 3, 4))
    report_date = Date.new(2025, 12, 31)
    fr = FinancialReport.create!(stock: stock, report_date: report_date, report_type: "CN_ANNUAL",
                                 market: "CN", period_type: "annual", currency: "CNY")
    indicator = FinancialIndicator.create!(financial_report: fr, stock: stock,
                                           report_date: report_date, market: "CN", period_type: "annual")
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2026-02-02 00:00:00",
        "KCFJCXSYJLR" => nil, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, stock, "301602.SZ", "CN")

    assert_equal 0, result[:gated]
    indicator.reload
    assert_equal Date.new(2026, 2, 2), indicator.disclosed_at
  end

  # 豁免仅覆盖上市日之前的披露日期；上市日之后（窗口外）的荒谬日期仍被拦截
  test "次新股上市日之后的窗口外日期仍被拦截" do
    stock = Stock.create!(symbol: "SZ301603", name: "测试深股二", market: "CN",
                          status: "active", listing_date: Date.new(2026, 3, 4))
    report_date = Date.new(2025, 12, 31)
    fr = FinancialReport.create!(stock: stock, report_date: report_date, report_type: "CN_ANNUAL",
                                 market: "CN", period_type: "annual", currency: "CNY")
    indicator = FinancialIndicator.create!(financial_report: fr, stock: stock,
                                           report_date: report_date, market: "CN", period_type: "annual")
    payload = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2030-01-01 00:00:00",
        "KCFJCXSYJLR" => nil, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }

    result = fetcher_with_payload(payload).send(:fetch_f10_supplement, stock, "301603.SZ", "CN")

    assert_equal 1, result[:gated]
    indicator.reload
    assert_nil indicator.disclosed_at
  end

  # 公告接口分页在收集齐所需年报年份后提前终止，不再翻满 6 页
  test "公告接口收集到所需年份后提前终止分页" do
    stock, indicator = bj_stock_with_indicator
    f10 = { "result" => { "data" => [
      { "REPORT_DATE" => "2025-12-31 00:00:00", "NOTICE_DATE" => "2026-02-25 00:00:00",
        "KCFJCXSYJLR" => nil, "ROEKCJQ" => nil, "EPSXS" => nil }
    ] } }
    ann = { "data" => { "list" => [
      { "title" => "彩客科技:2025年年度报告", "notice_date" => "2026-03-18 00:00:00" }
    ] } }
    fetcher = DataSources::Fetchers::CnFetcher.new
    ann_calls = 0
    fetcher.define_singleton_method(:http_get) do |url, **_kwargs|
      if url.to_s.include?("np-anotice")
        ann_calls += 1
        ann
      else
        f10
      end
    end

    fetcher.send(:fetch_f10_supplement, stock, "920206.BJ", "CN")

    assert_equal 1, ann_calls
    indicator.reload
    assert_equal Date.new(2026, 3, 18), indicator.disclosed_at
  end
end
