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

      # ROE avg = 30 -> 500分（线性插值端点不变）
      # ROA avg ≈ 6.45% → 0分(<7)
      # 净利润规模 avg ≈ 32.64亿 → 50分(盈利档，<100亿)
      # 资产周转率 avg ≈ 0.31 → 31% → 0分(<80%)
      # 毛利率 avg = 48.2% → 50分(>30%)
      # 净利润增长: 连年增且增幅>20% → 1.5倍权重，clamp至+90
      # 现金流增长: 连年增 → clamp至+90
      # 现金占比 avg ≈ 25% → 50分(≥20%档)
      # 总分 ≈ 500 + 0 + 50 + 0 + 50 + 90 + 90 + 50 = 830
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
      # ROA avg = 5%(10亿/200亿) → 0分(<7)
      # 净利润规模 avg = 10亿 → 50分(盈利档，<100亿)
      # 毛利率 avg = 40% → 50分
      # 现金占比 avg = 15%(30亿/200亿) → 本应25分，但ROE为负 → 现金分归零
      # 总分 ≈ 0+0+50+0+50+0+0+0 = 100
      score = result[:new_score]
      assert_equal 100, score, "负ROE应导致总分偏低且规模落入盈利档，实际得分=#{score}"
      assert_equal score, @stock.reload.pyramid_total_score
    end

    test "7. ROE 线性插值：边界附近连续计分，消除档位跳跃" do
      # 24.74%（如恺英网络）不应再因差0.26pp被卡在400档，插值应为447
      score = StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 24.74 } })
      assert_equal 447, score

      # 档位端点保持原语义
      assert_equal 400, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 20.0 } })
      assert_equal 450, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 25.0 } })
      assert_equal 550, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 35.0 } })

      # 低于10%不得分
      assert_equal 0, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 9.9 } })
    end

    test "8. 增长分档：增幅<5%半权、5%~20%全权、>20% 1.5倍；降幅<=5%不扣、5%~15%半扣、>15%全额扣" do
      # 权重[15,20,25,30]（近期权重高）：+30%*1.5 + 降1.5%不扣 + +17.2% + +20%*1.5 → 22.5+0+25+45 = 92.5 → 93，但超+90上限被clamp为90
      all_data1 = [100, 130, 128, 150, 180].map { |v| { net_income: v } }
      assert_equal 90, StockPyramidService.send(:calculate_net_profit_growth_score, nil, all_data1)

      # +30%*1.5 + +11.5% + 降10.3%半扣(-12.5) + +23%*1.5 → 22.5+20-12.5+45 = 75
      all_data2 = [100, 130, 145, 130, 160].map { |v| { net_income: v } }
      assert_equal 75, StockPyramidService.send(:calculate_net_profit_growth_score, nil, all_data2)

      # +30%*1.5 + 降23%全额(-20) + +20%*1.5 + +16.7% → 22.5-20+37.5+30 = 70
      all_data3 = [100, 130, 100, 120, 140].map { |v| { net_income: v } }
      assert_equal 70, StockPyramidService.send(:calculate_net_profit_growth_score, nil, all_data3)

      # 现金流增长分档逻辑一致
      all_data4 = [100, 130, 145, 130, 160].map { |v| { operating_cash_flow: v } }
      assert_equal 75, StockPyramidService.send(:calculate_cash_flow_growth_score, all_data4)
    end

    test "8a. 权重方向：近期增速权重高于远期（i=3 最近两年权重30 > i=0 最早两年权重15）" do
      # 仅最近两年 +30% → 仅 i=3 参与：30*1.5 = 45
      recent_growth = [100, 100, 100, 100, 130].map { |v| { net_income: v } }
      assert_equal 45, StockPyramidService.send(:calculate_net_profit_growth_score, nil, recent_growth)

      # 仅最早两年 +30% → 仅 i=0 参与：15*1.5 = 22.5 → 23
      early_growth = [100, 130, 130, 130, 130].map { |v| { net_income: v } }
      assert_equal 23, StockPyramidService.send(:calculate_net_profit_growth_score, nil, early_growth)
    end

    test "9. 负值年份不参与增长计分：亏损收窄不再被当作成长" do
      # [-100, -30, -10, 5, 20]：前3段含负值全部跳过，仅5→20(+300%)按1.5倍 → 30*1.5 = 45
      all_data = [-100, -30, -10, 5, 20].map { |v| { net_income: v } }
      assert_equal 45, StockPyramidService.send(:calculate_net_profit_growth_score, nil, all_data)

      # 连亏5年（亏损逐年收窄）不得正分
      all_data2 = [-140, -40, -29, -15, -10].map { |v| { net_income: v } }
      assert_equal 0, StockPyramidService.send(:calculate_net_profit_growth_score, nil, all_data2)

      # 盈利转亏损（正→负）是重大负面信号，全额扣分：100→-20是i=0段（最早两年），扣最低档15，其余含负值段跳过 → -15
      all_data3 = [100, -20, -5, -2, 1].map { |v| { net_income: v } }
      assert_equal(-15, StockPyramidService.send(:calculate_net_profit_growth_score, nil, all_data3))
      # 现金流增长逻辑一致
      all_data4 = [100, -20, -5, -2, 1].map { |v| { operating_cash_flow: v } }
      assert_equal(-15, StockPyramidService.send(:calculate_cash_flow_growth_score, all_data4))
    end

    test "10. ROA 去重：ROE高分(>=450)时ROA减半，ROE不高时ROA全额" do
      all_data = (1..5).map { { roa: 16.0 } }
      # ROE 500(≥450) → ROA 100*0.5 = 50
      assert_equal 50, StockPyramidService.send(:calculate_roa_score, all_data, 500)
      # ROE 300(<450) → ROA 100 全额
      assert_equal 100, StockPyramidService.send(:calculate_roa_score, all_data, 300)
    end

    test "11. 现金占比：权重降为50且ROE为负时归零" do
      # ROE为正 + 现金25% → 50分
      all_data1 = (1..5).map { { roe: 20.0, cash_to_assets_ratio: 25.0 } }
      assert_equal 50, StockPyramidService.send(:calculate_cash_ratio_score, all_data1)
      # ROE为正 + 现金12% → 25分
      all_data2 = (1..5).map { { roe: 20.0, cash_to_assets_ratio: 12.0 } }
      assert_equal 25, StockPyramidService.send(:calculate_cash_ratio_score, all_data2)
      # ROE存在负值 → 现金分归零（即使现金充足）
      all_data3 = (1..4).map { { roe: 20.0, cash_to_assets_ratio: 25.0 } } + [{ roe: -5.0, cash_to_assets_ratio: 25.0 }]
      assert_equal 0, StockPyramidService.send(:calculate_cash_ratio_score, all_data3)
      # ROE数据完全缺失 → 现金分归零（与ROE分"数据不足3年得0分"口径一致）
      all_data4 = (1..5).map { { cash_to_assets_ratio: 25.0 } }
      assert_equal 0, StockPyramidService.send(:calculate_cash_ratio_score, all_data4)
      # ROE数据不足3年（仅2年）→ 现金分归零
      all_data5 = (1..2).map { { roe: 20.0, cash_to_assets_ratio: 25.0 } } + (1..3).map { { cash_to_assets_ratio: 25.0 } }
      assert_equal 0, StockPyramidService.send(:calculate_cash_ratio_score, all_data5)
    end
  end
end
