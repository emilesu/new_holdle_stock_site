require "test_helper"

module DataSources
  class DataQualityServiceTest < ActiveSupport::TestCase
    setup do
      DataQualityIssue.delete_all
      @stock = Stock.where(market: "CN").order(:id).first
      skip "需要 CN 股票样本" if @stock.nil?
      # 置空上市日期，保证既有用例不受样本股真实上市日影响
      @stock.update_column(:listing_date, nil)
    end

    # ── 月K ──

    test "近月缺月时报缺月" do
      create_bar((Date.current - 5.months).end_of_month.to_s)
      create_bar((Date.current - 2.months).end_of_month.to_s)

      assert_equal 1, DataQualityService.check_monthly_bars(@stock)
      assert issue?("month_gap")
    end

    test "历史停牌造成的远期缺月不报缺月" do
      # 缺月结束于 2 年半前：无法与整月停牌区分，重抓也补不齐，不再报
      create_bar((Date.current - 36.months).end_of_month.to_s)
      create_bar((Date.current - 30.months).end_of_month.to_s)

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("month_gap")
    end

    test "连续月份不报缺月" do
      create_bar("2024-01-31")
      create_bar("2024-02-29")

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("month_gap")
    end

    test "历史缺月问题在复检通过后自动关闭" do
      issue = DataQualityIssue.record!(@stock, "monthly_bar", "month_gap")
      create_bar((Date.current - 2.months).end_of_month.to_s)
      create_bar((Date.current - 1.month).end_of_month.to_s)

      DataQualityService.check_monthly_bars(@stock)
      assert issue.reload.resolved_at.present?
      assert_equal "auto_resolved", issue.resolution
    end

    test "后复权因子下降时报错" do
      create_bar("2024-01-31", hfq_factor: 1.0)
      create_bar("2024-02-29", hfq_factor: 0.9)

      DataQualityService.check_monthly_bars(@stock)
      assert issue?("hfq_factor_decrease")
    end

    test "后复权因子舍入噪声不报因子下降" do
      create_bar("2024-01-31", hfq_factor: 1.0)
      create_bar("2024-02-29", hfq_factor: 0.9999999)

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("hfq_factor_decrease")
    end

    test "递推舍入噪声带（1e-6~1e-5）不报因子下降" do
      # 实测残留误报全部落在该区间：递推乘积按 scale 10 舍入的正常噪声
      create_bar("2024-01-31", hfq_factor: 1.0)
      create_bar("2024-02-29", hfq_factor: 0.999995)

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("hfq_factor_decrease")
    end

    test "前后复权常数关系偏离时报错" do
      create_bar("2024-01-31", qfq_close: 5, hfq_close: 10)
      create_bar("2024-02-29", qfq_close: 5.4, hfq_close: 11)

      DataQualityService.check_monthly_bars(@stock)
      assert issue?("ratio_deviation")
    end

    test "低价股复权比值舍入噪声不报偏离" do
      # 前复权 2 元档：半分钱舍入即可造成 ~0.25% 比值偏差，属噪声而非口径异常
      create_bar("2024-01-31", qfq_close: 2.00, hfq_close: 4.00)
      create_bar("2024-02-29", qfq_close: 2.01, hfq_close: 4.03)

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("ratio_deviation")
    end

    test "基准行为极低价行时其舍入噪声计入容差不误报" do
      # 首行（基准）前复权价仅 1 分钱：定点舍入使其比值本身偏离真常数可达百分之几，
      # 后续正常高价行的「偏差」实为基准行噪声，不应报
      create_bar("2024-01-31", qfq_close: 0.01, hfq_close: 0.02)
      create_bar("2024-02-29", qfq_close: 10.00, hfq_close: 20.30)

      assert_equal 0, DataQualityService.check_monthly_bars(@stock)
      refute issue?("ratio_deviation")
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
      # 窗口起点四表齐全（确立共同覆盖起点），一年前的期次只入库两张 → 应报
      create_period(Date.current - 3.years, %w[income balance cash indicator])
      create_period(Date.current - 1.year, %w[income balance])

      DataQualityService.check_financials(@stock)
      assert issue?("partial_period", data_type: "financial")
    end

    test "子表共同起点之前的历史期次不报期次不完整" do
      # 模拟数据源覆盖边界：现金流量表一年前才开始有数据，更早期次只入库三张表
      create_period(Date.current - 3.years, %w[income balance indicator])
      create_period(Date.current - 2.years, %w[income balance indicator])
      create_period(Date.current - 1.year, %w[income balance cash indicator])

      DataQualityService.check_financials(@stock)
      refute issue?("partial_period", data_type: "financial")
    end

    test "披露时滞窗口内的期次不报期次不完整" do
      create_period(Date.current - 3.years, %w[income balance cash indicator])
      # 刚过去的报告期：部分子表尚未披露，属正常时滞
      create_period(Date.current - 10.days, %w[income balance])

      DataQualityService.check_financials(@stock)
      refute issue?("partial_period", data_type: "financial")
    end

    test "检查窗口之外的历史散点缺失不报期次不完整" do
      # 四张表五年前都齐（共同起点在窗口外），四年半前只入库两张 → 超出近 4 年窗口，不报
      create_period(Date.current - 5.years, %w[income balance cash indicator])
      create_period(Date.current - 4.years - 6.months, %w[income balance])

      DataQualityService.check_financials(@stock)
      refute issue?("partial_period", data_type: "financial")
    end

    test "上市前招股期次只入库部分子表不报期次不完整" do
      # 模拟新股（如美股 SPAC）：数据源回溯披露上市前招股期次，但资产负债表回溯深度不一，
      # 四表起点相同使「覆盖边界」规则失效，须靠上市日期排除
      @stock.update_column(:listing_date, Date.current - 1.year)
      create_period(Date.current - 3.years, %w[income balance cash indicator])
      create_period(Date.current - 2.years, %w[income balance indicator])

      assert_equal 0, DataQualityService.check_financials(@stock)
      refute issue?("partial_period", data_type: "financial")
    end

    test "上市后部分子表缺失仍报期次不完整" do
      @stock.update_column(:listing_date, Date.current - 1.year)
      create_period(Date.current - 3.years, %w[income balance cash indicator])
      create_period(Date.current - 6.months, %w[income balance indicator])

      DataQualityService.check_financials(@stock)
      assert issue?("partial_period", data_type: "financial")
    end

    test "整只股票无数据的子表不参与完整性判定" do
      # 模拟数据源不覆盖该股票的财务指标：只入库三张表也不应报
      create_period(Date.current - 2.years, %w[income balance cash])
      create_period(Date.current - 1.year, %w[income balance cash])

      DataQualityService.check_financials(@stock)
      refute issue?("partial_period", data_type: "financial")
    end

    test "复检通过后自动关闭不再复现的期次不完整问题" do
      issue = DataQualityIssue.record!(@stock, "financial", "partial_period")
      create_period(Date.current - 1.year, %w[income balance cash indicator])

      DataQualityService.check_financials(@stock)
      assert issue.reload.resolved_at.present?
      assert_equal "auto_resolved", issue.resolution
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

    test "上市前招股期次关键字段为空不报关键字段为空" do
      # 招股期次的数据源本就残缺，营收/总资产全空不算质量问题
      @stock.update_column(:listing_date, Date.current - 1.year)
      create_period(Date.current - 2.years, %w[income balance])

      assert_equal 0, DataQualityService.check_financials(@stock)
      refute issue?("empty_financials", data_type: "financial")
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
      # 缺月须落在近 12 个月窗口内才会被检出（历史缺月视为停牌，不报）
      create_bar((Date.current - 5.months).end_of_month.to_s)
      create_bar((Date.current - 2.months).end_of_month.to_s)

      stats = DataQualityService.scan(market: "CN")
      assert_operator stats[:checked], :>=, 1
      assert_operator stats[:issues], :>=, 1
    end

    private

    # 按指定子表为一期报告期入库数据（tables: income/balance/cash/indicator）
    PERIOD_TABLES = {
      "income" => IncomeStatement, "balance" => BalanceSheet,
      "cash" => CashFlow, "indicator" => FinancialIndicator
    }.freeze

    def create_period(date, tables)
      report = FinancialReport.create!(stock: @stock, report_date: date,
                                       market: @stock.market, report_type: "annual")
      tables.each do |name|
        PERIOD_TABLES[name].create!(financial_report: report, stock: @stock,
                                     market: @stock.market, report_date: date)
      end
    end

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
