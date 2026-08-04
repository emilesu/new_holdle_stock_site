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
end
