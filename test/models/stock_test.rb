require "test_helper"

class StockTest < ActiveSupport::TestCase
  def setup
    @stock = Stock.create!(
      symbol: "TAG_TEST",
      name: "Tag Test Stock",
      market: "CN",
      exchange: "SH",
      sector: "消费",
      industry: "食品",
      status: "active"
    )
  end

  def teardown
    FinancialIndicator.where(stock_id: @stock.id).delete_all
    IncomeStatement.where(stock_id: @stock.id).delete_all
    FinancialReport.where(stock_id: @stock.id).delete_all
    @stock.destroy!
  end

  # 构造某股票某年的财务数据（指标表 + 利润表）
  def create_year(stock, year, roe:, net_income:)
    report_date = Date.new(year, 12, 31)
    report = FinancialReport.create!(stock: stock, report_date: report_date, market: "CN", report_type: "annual", currency: "CNY")
    FinancialIndicator.create!(financial_report: report, stock: stock, report_date: report_date, market: "CN", roe_avg: roe)
    IncomeStatement.create!(financial_report: report, stock: stock, report_date: report_date, market: "CN", net_income_to_shareholders: net_income)
  end

  test "pyramid_tags: 5年连续盈利无标签" do
    (2021..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    assert_equal [], @stock.reload.pyramid_tags
  end

  test "pyramid_tags: 数据不足5年标记'数据<5年'" do
    (2023..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    assert_equal ["数据<5年"], @stock.pyramid_tags
  end

  test "pyramid_tags: ROE为负的年份标记'亏损年份'" do
    (2021..2024).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    create_year(@stock, 2025, roe: -5.0, net_income: 50_0000_0000)
    assert_equal ["亏损年份"], @stock.pyramid_tags
  end

  test "pyramid_tags: 净利润为负也判定为亏损年份" do
    (2021..2024).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    create_year(@stock, 2025, roe: 20.0, net_income: -10_0000_0000)
    assert_equal ["亏损年份"], @stock.pyramid_tags
  end

  test "pyramid_tags: 数据不足且存在亏损，两个标签并存" do
    (2023..2024).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    create_year(@stock, 2025, roe: -5.0, net_income: 50_0000_0000)
    assert_equal ["数据<5年", "亏损年份"], @stock.pyramid_tags
  end

  test "pyramid_tags_for: 批量返回 stock_id => tags" do
    s2 = Stock.create!(symbol: "TAG_TEST2", name: "Tag Test 2", market: "CN", exchange: "SZ", sector: "消费", status: "active")
    s3 = Stock.create!(symbol: "TAG_TEST3", name: "Tag Test 3", market: "CN", exchange: "SZ", sector: "消费", status: "active")

    (2021..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) } # 无标签
    (2023..2025).each { |y| create_year(s2, y, roe: 20.0, net_income: 50_0000_0000) }      # 数据<5年
    (2021..2024).each { |y| create_year(s3, y, roe: 20.0, net_income: 50_0000_0000) }
    create_year(s3, 2025, roe: -5.0, net_income: 50_0000_0000)                              # 亏损年份

    tags = Stock.pyramid_tags_for([@stock.reload, s2.reload, s3.reload])
    assert_equal [], tags[@stock.id]
    assert_equal ["数据<5年"], tags[s2.id]
    assert_equal ["亏损年份"], tags[s3.id]
  ensure
    FinancialIndicator.where(stock_id: [s2&.id, s3&.id]).delete_all if s2 || s3
    IncomeStatement.where(stock_id: [s2&.id, s3&.id]).delete_all if s2 || s3
    FinancialReport.where(stock_id: [s2&.id, s3&.id]).delete_all if s2 || s3
    s2&.destroy!
    s3&.destroy!
  end

  test "pyramid_tags: 上市不足3年标记'次新股'" do
    (2021..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    @stock.update!(listing_date: Date.current - 2.years)
    assert_equal ["次新股"], @stock.pyramid_tags
  end

  test "pyramid_tags: 上市超过3年不打次新股标签" do
    (2021..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    @stock.update!(listing_date: Date.current - 5.years)
    assert_equal [], @stock.pyramid_tags
  end

  test "pyramid_tags: 无上市日期不打次新股标签" do
    (2021..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    @stock.update!(listing_date: nil)
    assert_equal [], @stock.pyramid_tags
  end

  test "pyramid_tags: 次新股与数据不足并存" do
    (2023..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    @stock.update!(listing_date: Date.current - 1.year)
    assert_equal ["数据<5年", "次新股"], @stock.pyramid_tags
  end

  test "pyramid_tags: 未来日期的异常数据不打次新股标签" do
    (2021..2025).each { |y| create_year(@stock, y, roe: 20.0, net_income: 50_0000_0000) }
    @stock.update!(listing_date: Date.current + 1.year)
    assert_equal [], @stock.pyramid_tags
  end

  test "pyramid_tag_hint: 返回标签提示文案" do
    assert_equal "上市不足3年，历史表现参考有限", Stock.pyramid_tag_hint("次新股")
    assert_equal "未知标签", Stock.pyramid_tag_hint("未知标签")
  end

  # ==== 期次（period_type）相关：年报列与右侧季报同比两列 ====

  # 构造指定期次的财务数据（指标表 + 利润表）
  def create_period(stock, period_type:, report_date:, roe:, net_income:, market: "CN")
    report = FinancialReport.create!(
      stock: stock, report_date: report_date, market: market,
      report_type: "annual", currency: "CNY", period_type: period_type
    )
    FinancialIndicator.create!(
      financial_report: report, stock: stock, report_date: report_date,
      market: market, period_type: period_type, roe_avg: roe
    )
    IncomeStatement.create!(
      financial_report: report, stock: stock, report_date: report_date,
      market: market, period_type: period_type, net_income_to_shareholders: net_income
    )
  end

  test "financial_years: 不包含季报年份" do
    create_period(@stock, period_type: "annual", report_date: Date.new(2024, 12, 31), roe: 20.0, net_income: 100)
    create_period(@stock, period_type: "h1", report_date: Date.new(2025, 6, 30), roe: 10.0, net_income: 50)
    create_period(@stock, period_type: "q1", report_date: Date.new(2026, 3, 31), roe: 5.0, net_income: 20)

    assert_equal [ "2024" ], @stock.reload.financial_years
  end

  test "financial_years: 最多返回最近 20 年" do
    (2000..2025).each do |y|
      create_period(@stock, period_type: "annual", report_date: Date.new(y, 12, 31), roe: 20.0, net_income: 100)
    end

    years = @stock.reload.financial_years
    assert_equal 20, years.size
    assert_equal "2006", years.first
    assert_equal "2025", years.last
  end

  test "get_financial_data_by_year: 同一年存在季报时不污染年报取数" do
    create_period(@stock, period_type: "annual", report_date: Date.new(2025, 12, 31), roe: 20.0, net_income: 900)
    create_period(@stock, period_type: "h1", report_date: Date.new(2025, 6, 30), roe: 8.0, net_income: 300)

    data = @stock.reload.get_financial_data_by_year("2025")
    assert_equal "annual", data[:period_type]
    assert_equal Date.new(2025, 12, 31), data[:report_date]
    assert_equal 900, data[:net_income].to_i
    assert_equal BigDecimal("20.0"), data[:roe]
  end

  test "get_financial_data_by_year: 仅存在季报时返回空指标（不误当年报）" do
    create_period(@stock, period_type: "h1", report_date: Date.new(2025, 6, 30), roe: 8.0, net_income: 300)

    data = @stock.reload.get_financial_data_by_year("2025")
    assert_nil data[:income_statement]
    assert_nil data[:net_income]
  end

  test "period_comparison_periods: 左为去年同期同一期次，右为最近一期" do
    create_period(@stock, period_type: "h1", report_date: Date.new(2025, 6, 30), roe: 18.0, net_income: 800)
    create_period(@stock, period_type: "h1", report_date: Date.new(2026, 6, 30), roe: 21.0, net_income: 1141)
    create_period(@stock, period_type: "q1", report_date: Date.new(2026, 3, 31), roe: 9.0, net_income: 400)

    periods = @stock.reload.period_comparison_periods
    assert_equal [ [ "h1", Date.new(2025, 6, 30) ], [ "h1", Date.new(2026, 6, 30) ] ],
                 periods.map { |p| [ p.period_type, p.report_date ] }
  end

  test "period_comparison_periods: 无季报时返回空数组（不渲染右侧两列）" do
    create_period(@stock, period_type: "annual", report_date: Date.new(2025, 12, 31), roe: 20.0, net_income: 900)

    assert_equal [], @stock.reload.period_comparison_periods
  end

  test "prior_year_same_period: 非 12 月财年按 120 天容差匹配去年同期" do
    create_period(@stock, period_type: "q3", report_date: Date.new(2025, 6, 28), roe: 15.0, net_income: 700, market: "US")
    create_period(@stock, period_type: "q3", report_date: Date.new(2026, 6, 27), roe: 17.0, net_income: 1014, market: "US")

    latest = @stock.reload.latest_quarter_period
    matched = @stock.prior_year_same_period(latest)
    assert_equal Date.new(2025, 6, 28), matched.report_date
  end

  test "recent_quarter_periods: 仅非年报且按报告期升序" do
    create_period(@stock, period_type: "annual", report_date: Date.new(2024, 12, 31), roe: 20.0, net_income: 900)
    create_period(@stock, period_type: "q3", report_date: Date.new(2025, 9, 30), roe: 15.0, net_income: 700)
    create_period(@stock, period_type: "q1", report_date: Date.new(2026, 3, 31), roe: 5.0, net_income: 200)
    create_period(@stock, period_type: "h1", report_date: Date.new(2025, 6, 30), roe: 10.0, net_income: 400)

    dates = @stock.reload.recent_quarter_periods.map(&:report_date)
    assert_equal [ Date.new(2025, 6, 30), Date.new(2025, 9, 30), Date.new(2026, 3, 31) ], dates
  end

  test "period_label: 期次中文标签" do
    assert_equal "2026中报", @stock.period_label("h1", Date.new(2026, 6, 30))
    assert_equal "2025三季报", @stock.period_label("q3", Date.new(2025, 9, 30))
    assert_equal "2026一季报", @stock.period_label("q1", Date.new(2026, 3, 31))
    assert_equal "2025年报", @stock.period_label("annual", Date.new(2025, 12, 31))
    assert_nil @stock.period_label("h1", nil)
  end

  test "cached_detail_financials: 年报列与季报同比列口径分离" do
    create_period(@stock, period_type: "annual", report_date: Date.new(2024, 12, 31), roe: 20.0, net_income: 900)
    create_period(@stock, period_type: "annual", report_date: Date.new(2025, 12, 31), roe: 22.0, net_income: 950)
    create_period(@stock, period_type: "h1", report_date: Date.new(2025, 6, 30), roe: 10.0, net_income: 400)
    create_period(@stock, period_type: "h1", report_date: Date.new(2026, 6, 30), roe: 12.0, net_income: 480)

    detail = @stock.reload.cached_detail_financials
    assert_equal %w[2024 2025], detail[:annual].keys
    assert_equal [ "2025中报", "2026中报" ], detail[:quarters].map { |q| q[:label] }
    assert_equal 480, detail[:quarters].last[:data][:net_income].to_i
  end
end
