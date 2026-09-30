require "test_helper"

module DataSources
  class DataQualityServiceTest < ActiveSupport::TestCase
    setup do
      DataQualityIssue.delete_all
      @stock = Stock.where(market: "CN").order(:id).first
      skip "需要 CN 股票样本" if @stock.nil?
    end

    # ── 月K ──

    test "相邻月K间隔超过一个月时报缺月" do
      create_bar("2024-01-31")
      create_bar("2024-04-30")

      assert_equal 1, DataQualityService.check_monthly_bars(@stock)
      assert issue?("month_gap")
    end

    test "连续月份不报缺月" do
      create_bar("2024-01-31")
      create_bar("2024-02-29")

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("month_gap")
    end

    test "后复权因子下降时报错" do
      create_bar("2024-01-31", hfq_factor: 1.0)
      create_bar("2024-02-29", hfq_factor: 0.9)

      DataQualityService.check_monthly_bars(@stock)
      assert issue?("hfq_factor_decrease")
    end

    test "前后复权常数关系偏离时报错" do
      create_bar("2024-01-31", qfq_close: 5, hfq_close: 10)
      create_bar("2024-02-29", qfq_close: 5.4, hfq_close: 11)

      DataQualityService.check_monthly_bars(@stock)
      assert issue?("ratio_deviation")
    end

    test "前后复权保持常数关系时不报错" do
      create_bar("2024-01-31", qfq_close: 5, hfq_close: 10)
      create_bar("2024-02-29", qfq_close: 6, hfq_close: 12)

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
    end

    test "月K不足两行时不做判定" do
      create_bar("2024-01-31")
      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
    end

    # ── 财务 ──

    test "同一报告期只入库部分子表时报期次不完整" do
      report = FinancialReport.create!(stock: @stock, report_date: Date.new(2024, 12, 31),
                                       market: @stock.market, report_type: "annual")
      IncomeStatement.create!(financial_report: report, stock: @stock, market: @stock.market,
                              report_date: report.report_date, total_revenue: 100)

      DataQualityService.check_financials(@stock)
      assert issue?("partial_period", data_type: "financial")
    end

    test "四张子表齐全时不报期次不完整" do
      report = FinancialReport.create!(stock: @stock, report_date: Date.new(2023, 12, 31),
                                       market: @stock.market, report_type: "annual")
      date = report.report_date
      IncomeStatement.create!(financial_report: report, stock: @stock, market: @stock.market,
                              report_date: date, total_revenue: 100)
      BalanceSheet.create!(financial_report: report, stock: @stock, market: @stock.market,
                           report_date: date, total_assets: 200)
      CashFlow.create!(financial_report: report, stock: @stock, market: @stock.market, report_date: date)
      FinancialIndicator.create!(financial_report: report, stock: @stock, market: @stock.market, report_date: date)

      DataQualityService.check_financials(@stock)
      refute issue?("partial_period", data_type: "financial")
    end

    test "营收与总资产同时为空时报关键字段为空" do
      report = FinancialReport.create!(stock: @stock, report_date: Date.new(2022, 12, 31),
                                       market: @stock.market, report_type: "annual")
      date = report.report_date
      IncomeStatement.create!(financial_report: report, stock: @stock, market: @stock.market,
                              report_date: date, total_revenue: nil)
      BalanceSheet.create!(financial_report: report, stock: @stock, market: @stock.market,
                           report_date: date, total_assets: nil)

      DataQualityService.check_financials(@stock)
      assert issue?("empty_financials", data_type: "financial")
    end

    test "财报日期在未来时报错" do
      FinancialReport.create!(stock: @stock, report_date: Date.current + 1.year,
                              market: @stock.market, report_type: "annual")

      DataQualityService.check_financials(@stock)
      assert issue?("future_report_date", data_type: "financial")
    end

    test "没有任何财务记录时不判定" do
      other = Stock.where.not(id: FinancialReport.select(:stock_id)).first
      skip "所有股票都有财务记录" if other.nil?

      assert_equal 0, DataQualityService.check_financials(other)
    end

    test "scan 只扫描有数据的股票" do
      create_bar("2024-01-31")
      create_bar("2024-04-30")

      stats = DataQualityService.scan(market: "CN")
      assert_operator stats[:checked], :>=, 1
      assert_operator stats[:issues], :>=, 1
    end

    private

    def create_bar(date, hfq_factor: 1, qfq_close: 10, hfq_close: 10)
      StockMonthlyBar.create!(
        stock: @stock, market: @stock.market, trade_date: Date.parse(date),
        hfq_factor: hfq_factor, qfq_close: qfq_close, hfq_close: hfq_close
      )
    end

    def issue?(issue_type, data_type: "monthly_bar")
      DataQualityIssue.open.of_type(data_type).exists?(issue_type: issue_type)
    end
  end
end
