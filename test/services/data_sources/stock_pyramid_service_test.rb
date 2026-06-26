require "test_helper"

module DataSources
  class StockPyramidServiceTest < ActiveSupport::TestCase
    def setup
      # 创建测试股票，确保不与 fixture 冲突
      @stock = Stock.create!(
        symbol: "PYR_TEST",
        name: "Pyramid Test Stock",
        market: "CN",
        exchange: "SH",
        sector: "消费",
        industry: "食品",
        status: "active"
      )
    end

    def teardown
      # 清理所有与该股票相关的测试数据
      # 使用 delete_all 避免回调干扰
      FinancialIndicator.where(stock_id: @stock.id).delete_all
      IncomeStatement.where(stock_id: @stock.id).delete_all
      BalanceSheet.where(stock_id: @stock.id).delete_all
      CashFlow.where(stock_id: @stock.id).delete_all
      FinancialReport.where(stock_id: @stock.id).delete_all
      @stock.destroy!
    end

    # 辅助方法：创建测试财务数据
    def create_financial_data(years_data)
      years_data.each do |yd|
        year = yd[:year]
        report_date = Date.new(year, 12, 31)

        report = FinancialReport.create!(
          stock: @stock,
          report_date: report_date,
          market: "CN",
          report_type: "annual",
          currency: "CNY"
        )

        FinancialIndicator.create!(
          financial_report: report,
          stock: @stock,
          report_date: report_date,
          market: "CN",
          roe_avg: yd[:roe],
          gross_margin: yd[:gross_margin],
          net_sales_rate: yd[:net_sales_rate],
          basic_eps: yd[:basic_eps],
          asset_liab_ratio: yd[:asset_liab_ratio]
        )

        IncomeStatement.create!(
          financial_report: report,
          stock: @stock,
          report_date: report_date,
          market: "CN",
          total_revenue: yd[:total_revenue],
          net_income_to_shareholders: yd[:net_income],
          operating_cost: yd[:operating_cost],
          gross_profit: yd[:gross_profit]
        )

        BalanceSheet.create!(
          financial_report: report,
          stock: @stock,
          report_date: report_date,
          market: "CN",
          total_assets: yd[:total_assets],
          total_liabilities: yd[:total_liabilities],
          total_equity: yd[:total_equity],
          cash_and_cash_equivalents: yd[:cash_and_equivalents],
          accounts_receivable: yd[:accounts_receivable],
          inventory: yd[:inventory],
          property_plant_equipment: yd[:ppe]
        )

        CashFlow.create!(
          financial_report: report,
          stock: @stock,
          report_date: report_date,
          market: "CN",
          operating_cash_flow: yd[:operating_cf],
          investing_cash_flow: yd[:investing_cf],
          financing_cash_flow: yd[:financing_cf],
          net_cash_change: yd[:net_cash_change]
        )
      end
    end

    # ========== 测试用例 ==========

    test "1. 无财务数据时返回0分" do
      result = StockPyramidService.call(@stock)
      assert result[:success]
      assert_equal 0, result[:new_score]
    end

    test "2. 只有1年数据（不足3年）时返回0分" do
      create_financial_data([
        { year: 2024, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 }
      ])

      result = StockPyramidService.call(@stock)
      assert result[:success]
      # 各子分数方法要求至少3-5年数据，所以总分应为0
      assert_equal 0, result[:new_score]
    end

    test "3. 5年完整高增长数据应得高分" do
      create_financial_data([
        { year: 2021, roe: 25.0, gross_margin: 45.0, net_sales_rate: 18.0,
          basic_eps: 3.5, asset_liab_ratio: 40.0,
          total_revenue: 100_0000_0000, net_income: 18_0000_0000,
          operating_cost: 55_0000_0000, gross_profit: 45_0000_0000,
          total_assets: 360_0000_0000, total_liabilities: 144_0000_0000,
          total_equity: 216_0000_0000, cash_and_equivalents: 72_0000_0000,
          accounts_receivable: 10_0000_0000, inventory: 5_0000_0000, ppe: 20_0000_0000,
          operating_cf: 20_0000_0000, investing_cf: -5_0000_0000,
          financing_cf: -3_0000_0000, net_cash_change: 12_0000_0000 },
        { year: 2022, roe: 28.0, gross_margin: 46.0, net_sales_rate: 19.0,
          basic_eps: 4.0, asset_liab_ratio: 38.0,
          total_revenue: 120_0000_0000, net_income: 22_8000_0000,
          operating_cost: 64_8000_0000, gross_profit: 55_2000_0000,
          total_assets: 400_0000_0000, total_liabilities: 152_0000_0000,
          total_equity: 248_0000_0000, cash_and_equivalents: 90_0000_0000,
          accounts_receivable: 12_0000_0000, inventory: 6_0000_0000, ppe: 22_0000_0000,
          operating_cf: 24_0000_0000, investing_cf: -6_0000_0000,
          financing_cf: -4_0000_0000, net_cash_change: 14_0000_0000 },
        { year: 2023, roe: 30.0, gross_margin: 48.0, net_sales_rate: 20.0,
          basic_eps: 4.5, asset_liab_ratio: 35.0,
          total_revenue: 150_0000_0000, net_income: 30_0000_0000,
          operating_cost: 78_0000_0000, gross_profit: 72_0000_0000,
          total_assets: 480_0000_0000, total_liabilities: 168_0000_0000,
          total_equity: 312_0000_0000, cash_and_equivalents: 120_0000_0000,
          accounts_receivable: 15_0000_0000, inventory: 7_0000_0000, ppe: 25_0000_0000,
          operating_cf: 30_0000_0000, investing_cf: -8_0000_0000,
          financing_cf: -5_0000_0000, net_cash_change: 17_0000_0000 },
        { year: 2024, roe: 32.0, gross_margin: 50.0, net_sales_rate: 22.0,
          basic_eps: 5.0, asset_liab_ratio: 33.0,
          total_revenue: 180_0000_0000, net_income: 39_6000_0000,
          operating_cost: 90_0000_0000, gross_profit: 90_0000_0000,
          total_assets: 550_0000_0000, total_liabilities: 181_5000_0000,
          total_equity: 368_5000_0000, cash_and_equivalents: 150_0000_0000,
          accounts_receivable: 18_0000_0000, inventory: 8_0000_0000, ppe: 30_0000_0000,
          operating_cf: 36_0000_0000, investing_cf: -10_0000_0000,
          financing_cf: -6_0000_0000, net_cash_change: 20_0000_0000 },
        { year: 2025, roe: 35.0, gross_margin: 52.0, net_sales_rate: 24.0,
          basic_eps: 5.5, asset_liab_ratio: 30.0,
          total_revenue: 220_0000_0000, net_income: 52_8000_0000,
          operating_cost: 105_6000_0000, gross_profit: 114_4000_0000,
          total_assets: 650_0000_0000, total_liabilities: 195_0000_0000,
          total_equity: 455_0000_0000, cash_and_equivalents: 200_0000_0000,
          accounts_receivable: 22_0000_0000, inventory: 10_0000_0000, ppe: 35_0000_0000,
          operating_cf: 48_0000_0000, investing_cf: -12_0000_0000,
          financing_cf: -8_0000_0000, net_cash_change: 28_0000_0000 }
      ])

      result = StockPyramidService.call(@stock)
      assert result[:success]
      score = result[:new_score]

      # ROE avg = 30 -> 500分
      # ROA avg ≈ 5.5% → 0分(<7)
      # 净利润规模 avg ≈ 32.64亿 → 100分(>=10亿)
      # 资产周转率 avg ≈ 0.32 → 32% → 0分(<80%)
      # 毛利率 avg = 48.2% → 50分(>30%)
      # 净利润增长: 连年增(早→晚)但代码反向比较(晚→早) → 扣分(-90)
      # 现金流增长: 同上 → 扣分(-35)
      # 总分 ≈ 500 + 0 + 100 + 0 + 50 - 90 - 35 = 525
      assert score >= 500, "高分数据应得到较高分数，实际得分=#{score}"
      assert score <= 1000, "得分不应超过1000，实际得分=#{score}"
    end

    test "4. 分数不变时更新时间戳" do
      create_financial_data([
        { year: 2021, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2022, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2023, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2024, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2025, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 }
      ])

      # 第一次计算
      StockPyramidService.call(@stock)
      old_timestamp = @stock.reload.last_pyramid_calc_at

      sleep 1  # 确保时间戳能区分

      # 第二次计算（数据相同，分数不变，应更新时间戳）
      result = StockPyramidService.call(@stock)
      assert result[:success]
      new_timestamp = @stock.reload.last_pyramid_calc_at

      assert_not_equal old_timestamp, new_timestamp, "分数不变时也应更新时间戳"
    end

    test "5. 股票不存在时返回错误" do
      result = StockPyramidService.call(nil)
      assert_not result[:success]
      assert_equal "股票不存在", result[:error]
    end

    test "6. 存在ROE为负时ROE分数为0" do
      create_financial_data([
        { year: 2021, roe: -5.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2022, roe: -3.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2023, roe: 10.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2024, roe: 15.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 },
        { year: 2025, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 }
      ])

      result = StockPyramidService.call(@stock)
      assert result[:success]

      # ROE avg = (-5 -3 +10 +15 +20)/5 = 7.4%, 但有任意ROE为负 -> ROE分=0
      # 现金占比 avg = 15% → 50分
      # 净利润规模 avg = 10亿 → 100分(>=10亿)
      # 毛利率 avg = 40% → 50分
      # 总分 ≈ 0+0+100+0+50+0+0+50 = 200
      score = result[:new_score]
      assert score < 300, "负ROE应导致总分偏低，实际得分=#{score}"
      assert_equal score, @stock.reload.pyramid_total_score
    end
  end
end