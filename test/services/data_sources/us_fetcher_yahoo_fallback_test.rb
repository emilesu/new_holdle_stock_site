require "test_helper"
require "minitest/mock"

# UsFetcher 财务指标 Yahoo 回退：东财两接口均空时用 Yahoo 补年报指标
# 覆盖：期次「同年同月」对齐、非匹配期次剔除、分页作废不回退、双源皆空记 failed
class UsFetcherYahooFallbackTest < ActiveSupport::TestCase
  Fetcher = DataSources::Fetchers::UsFetcher
  Yahoo = DataSources::YahooIndicatorService

  EMPTY_EM = { "result" => { "data" => [], "pages" => 1 } }.freeze

  setup do
    @stock = Stock.create!(symbol: "SOFI", name: "回退测试", market: "US")
    @periods = [
      { report_date: Date.new(2025, 12, 31), period_type: "annual" },
      { report_date: Date.new(2024, 12, 31), period_type: "annual" },
      { report_date: Date.new(2025, 6, 30), period_type: "h1" }
    ]
    @fetcher = Fetcher.new
  end

  test "东财两接口均空时回退 Yahoo 并按同年同月写入年报指标" do
    yahoo = {
      "2025-12" => { basic_eps: BigDecimal("1.1"), gross_margin: BigDecimal("40.0") },
      "2024-12" => { basic_eps: BigDecimal("0.46"), gross_margin: BigDecimal("35.5") },
      "2023-12" => { basic_eps: BigDecimal("-0.36") } # 站内无该期次，应被剔除
    }
    stub_eastmoney_empty

    result = Yahoo.stub(:fetch_annual, yahoo) do
      @fetcher.send(:fetch_and_save_indicator, @stock, "SOFI.O", "US", @periods)
    end

    assert_equal :success, result[:status]
    assert_equal 2, result[:count]
    assert_equal 2, FinancialIndicator.where(stock_id: @stock.id, period_type: "annual").count
    indicator = FinancialIndicator.find_by(stock_id: @stock.id, report_date: Date.new(2025, 12, 31))
    assert_equal BigDecimal("1.1"), indicator.basic_eps
    assert_equal BigDecimal("40.0"), indicator.gross_margin
    assert_nil FinancialIndicator.find_by(stock_id: @stock.id, report_date: Date.new(2023, 12, 31)),
               "站内期次白名单外的 Yahoo 期次不得入库"
  end

  test "Yahoo 亦无数据时记 failed 不落库" do
    stub_eastmoney_empty

    result = Yahoo.stub(:fetch_annual, {}) do
      @fetcher.send(:fetch_and_save_indicator, @stock, "SOFI.O", "US", @periods)
    end

    assert_equal :failed, result[:status]
    assert_equal 0, FinancialIndicator.where(stock_id: @stock.id).count
  end

  test "东财分页作废（nil）时不回退 Yahoo" do
    # 主/备接口均谎报 pages=99 且每页满行 → 翻到 MAX_PERIOD_PAGES 上限作废返回 nil
    @fetcher.define_singleton_method(:http_get) do |_url, _opts|
      { "result" => { "data" => Array.new(5000) { |i| { "REPORT_DATE" => "2025-12-31" } }, "pages" => 99 } }
    end
    yahoo_called = false
    recorder = ->(_stock) { yahoo_called = true; {} }

    Yahoo.stub(:fetch_annual, recorder) do
      result = @fetcher.send(:fetch_and_save_indicator, @stock, "SOFI.O", "US", @periods)
      assert_equal :failed, result[:status]
    end
    assert_not yahoo_called, "分页作废场景不得触发 Yahoo 回退"
  end

  test "Yahoo 数据与站内期次无一匹配时记 failed" do
    stub_eastmoney_empty

    result = Yahoo.stub(:fetch_annual, { "2019-12" => { basic_eps: BigDecimal("0.1") } }) do
      @fetcher.send(:fetch_and_save_indicator, @stock, "SOFI.O", "US", @periods)
    end

    assert_equal :failed, result[:status]
    assert_equal 0, FinancialIndicator.where(stock_id: @stock.id).count
  end

  # 核心对齐场景：非自然年财年（如 AAPL 9 月末），东财 report_date 为实际财年截止日（09-27），
  # Yahoo asOfDate 归到月末（09-30）——「同年同月不同日」必须能匹配入库
  test "期次对齐容忍日差：东财 09-27 与 Yahoo 09-30 同年同月即匹配" do
    shifted_stock = Stock.create!(symbol: "AAPLX", name: "错位对齐测试", market: "US")
    shifted_periods = [{ report_date: Date.new(2025, 9, 27), period_type: "annual" }]
    yahoo = { "2025-09" => { basic_eps: BigDecimal("7.49"), roe_avg: BigDecimal("171.40") } }

    fetcher = Fetcher.new
    fetcher.define_singleton_method(:http_get) { |_url, _opts| EMPTY_EM }

    result = Yahoo.stub(:fetch_annual, yahoo) do
      fetcher.send(:fetch_and_save_indicator, shifted_stock, "AAPLX.O", "US", shifted_periods)
    end

    assert_equal :success, result[:status]
    indicator = FinancialIndicator.find_by(stock_id: shifted_stock.id, report_date: Date.new(2025, 9, 27))
    assert_not_nil indicator, "应按同年同月匹配到站内 09-27 期次"
    assert_equal BigDecimal("7.49"), indicator.basic_eps
    assert_equal BigDecimal("171.40"), indicator.roe_avg
  end

  private

  def stub_eastmoney_empty
    @fetcher.define_singleton_method(:http_get) { |_url, _opts| EMPTY_EM }
  end
end
