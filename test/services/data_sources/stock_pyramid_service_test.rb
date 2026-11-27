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
          asset_liab_ratio: yd[:asset_liab_ratio],
          unlevered_roe: yd[:unlevered_roe],
          unlevered_roe_flag: yd[:unlevered_roe_flag]
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

    # ========== 集成用例（call 全流程） ==========

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

    test "3. 5年完整高增长数据应得高分（方案B全项累加精确校验）" do
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

      # ROE加权均值 = (25+28+60+96+105)/10 = 31.4 → 插值514 → ×400/550 = 373.8 → 374；稳定分150（全≥15%）→ 524
      # ROA avg ≈ 6.45% → 0分(<7)
      # 净利润规模 avg ≈ 32.64亿 → 50分(盈利档)
      # 资产周转率 avg ≈ 0.31 → 0分(<0.8次)
      # 毛利率 avg 48.2% → 水平45(≥40) + 稳定20(极差7pp<10) → 65
      # 净利润增长: 连年增且增幅>20% → clamp至+90
      # 现金流增长: 连年增 → clamp至+90
      # 现金占比 avg ≈ 25% → 50分(≥20%档)
      # 净现比 avg ≈ 0.996 → 30分(≥0.8档)
      # 总分 = 524+0+50+0+65+90+90+50+30 = 899
      assert_equal 899, score, "方案B全项累加应得899分，实际得分=#{score}"
    end

    test "4. 分数不变时更新时间戳" do
      flat_year = lambda do |year|
        { year: year, roe: 20.0, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 }
      end
      create_financial_data((2021..2025).map { |y| flat_year.call(y) })

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

    test "6. 存在ROE为负时ROE两项归零且现金分归零" do
      flat_year = lambda do |year, roe|
        { year: year, roe: roe, gross_margin: 40.0, net_sales_rate: 15.0,
          basic_eps: 2.0, asset_liab_ratio: 50.0,
          total_revenue: 100_0000_0000, net_income: 10_0000_0000,
          operating_cost: 60_0000_0000, gross_profit: 40_0000_0000,
          total_assets: 200_0000_0000, total_liabilities: 100_0000_0000,
          total_equity: 100_0000_0000, cash_and_equivalents: 30_0000_0000,
          accounts_receivable: 5_0000_0000, inventory: 3_0000_0000, ppe: 10_0000_0000,
          operating_cf: 8_0000_0000, investing_cf: -2_0000_0000,
          financing_cf: -1_0000_0000, net_cash_change: 5_0000_0000 }
      end
      create_financial_data([
        flat_year.call(2021, -5.0), flat_year.call(2022, -3.0),
        flat_year.call(2023, 10.0), flat_year.call(2024, 15.0), flat_year.call(2025, 20.0)
      ])

      result = StockPyramidService.call(@stock)
      assert result[:success]

      # ROE任一年≤0 → 水平+稳定全归零；ROA 5% → 0；规模10亿 → 50；周转0.5 → 0
      # 毛利率 avg 40% → 45 + 稳定40（极差0）= 85；增长/现金流持平 → 0
      # 现金占比15%但ROE有负值 → 0；净现比 0.8 → 30
      # 总分 = 50 + 85 + 30 = 165
      score = result[:new_score]
      assert_equal 165, score, "负ROE应导致ROE/现金分归零，实际得分=#{score}"
      assert_equal score, @stock.reload.pyramid_total_score
    end

    # ========== ROE 单元用例（水平分 + 稳定分） ==========

    test "7. ROE线性插值与400/550等比压缩" do
      # 24.74% → 插值447.4 → ×400/550 = 325.4 → 325；稳定分150（全≥15%）
      roe = StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 24.74 } })
      assert_equal({ level: 325, stability: 150 }, roe)

      # 档位端点：20→400×0.727=291；25→450×0.727=327；35→550→400
      assert_equal 291, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 20.0 } })[:level]
      assert_equal 327, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 25.0 } })[:level]
      assert_equal 400, StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 35.0 } })[:level]

      # 低于10%：水平0，稳定分40（>0但<10%）
      roe_low = StockPyramidService.send(:calculate_roe_score, (1..5).map { { roe: 9.9 } })
      assert_equal({ level: 0, stability: 40 }, roe_low)

      # 任一年≤0 → 两项全归零
      assert_equal({ level: 0, stability: 0 }, StockPyramidService.send(:calculate_roe_score, [{ roe: 20 }, { roe: -1 }, { roe: 20 }]))
      # 不足3年 → 两项全归零
      assert_equal({ level: 0, stability: 0 }, StockPyramidService.send(:calculate_roe_score, [{ roe: 20 }, { roe: 25 }]))
    end

    test "7a. ROE稳定分三档：全≥15%→150 / 全≥10%→100 / 其余→40" do
      assert_equal 150, StockPyramidService.send(:calculate_roe_score, [16, 18, 20, 22, 25].map { |v| { roe: v } })[:stability]
      assert_equal 100, StockPyramidService.send(:calculate_roe_score, [10, 12, 15, 18, 20].map { |v| { roe: v } })[:stability]
      assert_equal 40, StockPyramidService.send(:calculate_roe_score, [8, 12, 15, 18, 20].map { |v| { roe: v } })[:stability]
    end

    test "7b. ROE近年加权：尾部高ROE比简单均值获得更高分" do
      # [10,10,10,30,30] 加权均值 = (10+10+20+90+90)/10 = 22 → 插值420 → ×400/550 = 305.5 → 305
      # 若仍用简单均值18 → 380×0.727=276，加权后应显著更高
      roe = StockPyramidService.send(:calculate_roe_score, [10, 10, 10, 30, 30].map { |v| { roe: v } })
      assert_equal 305, roe[:level]
      assert_equal 100, roe[:stability]  # 全≥10% 但含<15%年份
    end

    test "7c. 衰退折扣：近3年均值 < 全期简单均值×0.7 → 水平分×0.8" do
      # [40,40,40,10,5] 加权均值20.5 → 插值405 → ×400/550=294.5 → ×0.8=235.6 → 236
      # 近3年均值18.33 < 全期均值27×0.7=18.9 触发
      roe = StockPyramidService.send(:calculate_roe_score, [40, 40, 40, 10, 5].map { |v| { roe: v } })
      assert_equal 236, roe[:level]

      # 数据仅3年时近3年即全期，不触发折扣：[30,30,30] 加权30 → 500×0.727=363.6 → 364
      roe3 = StockPyramidService.send(:calculate_roe_score, [30, 30, 30].map { |v| { roe: v } })
      assert_equal 364, roe3[:level]
    end

    test "7d. 杠杆质量调节：无杠杆ROE/ROE比值分档打折" do
      # 比值 20/30=0.667 → ≥0.55档 → ×0.8：500×0.727=363.6×0.8=290.9 → 291
      leveraged = (1..5).map { { roe: 30.0, unlevered_roe: 20.0 } }
      assert_equal 291, StockPyramidService.send(:calculate_roe_score, leveraged)[:level]

      # 比值 27/30=0.9 → ≥0.85档 → ×1.0 → 364
      healthy = (1..5).map { { roe: 30.0, unlevered_roe: 27.0 } }
      assert_equal 364, StockPyramidService.send(:calculate_roe_score, healthy)[:level]

      # 比值 15/30=0.5 → 兜底档 ×0.7 → 363.6×0.7=254.5 → 255
      heavy = (1..5).map { { roe: 30.0, unlevered_roe: 15.0 } }
      assert_equal 255, StockPyramidService.send(:calculate_roe_score, heavy)[:level]

      # 无杠杆数据仅2年 → 不惩罚（×1.0）
      sparse = [{ roe: 30.0, unlevered_roe: 10.0 }, { roe: 30.0, unlevered_roe: 10.0 }] +
               (1..3).map { { roe: 30.0 } }
      assert_equal 364, StockPyramidService.send(:calculate_roe_score, sparse)[:level]
    end

    test "7e. 4倍波动规则已移除：均值≥25%且极差悬殊不再封顶" do
      # [25,25,25,25,105] max/min=4.2>4，旧规则封顶450；新规则按加权均值47.8%≥35%给满400
      roe = StockPyramidService.send(:calculate_roe_score, [25, 25, 25, 25, 105].map { |v| { roe: v } })
      assert_equal 400, roe[:level]
    end

    # ========== 其余计分项单元用例 ==========

    test "8. 增长分档：增幅<5%半权、5%~20%全权、>20% 1.5倍；降幅<=5%不扣、5%~15%半扣、>15%全额扣" do
      # 权重[15,20,25,30]（近期权重高）：+30%*1.5 + 降1.5%不扣 + +17.2% + +20%*1.5 → 22.5+0+25+45 = 92.5 → 93，但超+90上限被clamp为90
      all_data1 = [100, 130, 128, 150, 180].map { |v| { net_income: v } }
      assert_equal 90, StockPyramidService.send(:calculate_net_profit_growth_score, all_data1)

      # +30%*1.5 + +11.5% + 降10.3%半扣(-12.5) + +23%*1.5 → 22.5+20-12.5+45 = 75
      all_data2 = [100, 130, 145, 130, 160].map { |v| { net_income: v } }
      assert_equal 75, StockPyramidService.send(:calculate_net_profit_growth_score, all_data2)

      # +30%*1.5 + 降23%全额(-20) + +20%*1.5 + +16.7% → 22.5-20+37.5+30 = 70
      all_data3 = [100, 130, 100, 120, 140].map { |v| { net_income: v } }
      assert_equal 70, StockPyramidService.send(:calculate_net_profit_growth_score, all_data3)

      # 现金流增长分档逻辑一致
      all_data4 = [100, 130, 145, 130, 160].map { |v| { operating_cash_flow: v } }
      assert_equal 75, StockPyramidService.send(:calculate_cash_flow_growth_score, all_data4)
    end

    test "8a. 权重方向：近期增速权重高于远期（i=3 最近两年权重30 > i=0 最早两年权重15）" do
      # 仅最近两年 +30% → 仅 i=3 参与：30*1.5 = 45
      recent_growth = [100, 100, 100, 100, 130].map { |v| { net_income: v } }
      assert_equal 45, StockPyramidService.send(:calculate_net_profit_growth_score, recent_growth)

      # 仅最早两年 +30% → 仅 i=0 参与：15*1.5 = 22.5 → 23
      early_growth = [100, 130, 130, 130, 130].map { |v| { net_income: v } }
      assert_equal 23, StockPyramidService.send(:calculate_net_profit_growth_score, early_growth)
    end

    test "9. 负值年份不参与增长计分：亏损收窄不再被当作成长" do
      # [-100, -30, -10, 5, 20]：前3段含负值全部跳过，仅5→20(+300%)按1.5倍 → 30*1.5 = 45
      all_data = [-100, -30, -10, 5, 20].map { |v| { net_income: v } }
      assert_equal 45, StockPyramidService.send(:calculate_net_profit_growth_score, all_data)

      # 连亏5年（亏损逐年收窄）不得正分
      all_data2 = [-140, -40, -29, -15, -10].map { |v| { net_income: v } }
      assert_equal 0, StockPyramidService.send(:calculate_net_profit_growth_score, all_data2)

      # 盈利转亏损（正→负）是重大负面信号，全额扣分：100→-20是i=0段（最早两年），扣最低档15，其余含负值段跳过 → -15
      all_data3 = [100, -20, -5, -2, 1].map { |v| { net_income: v } }
      assert_equal(-15, StockPyramidService.send(:calculate_net_profit_growth_score, all_data3))
      # 现金流增长逻辑一致
      all_data4 = [100, -20, -5, -2, 1].map { |v| { operating_cash_flow: v } }
      assert_equal(-15, StockPyramidService.send(:calculate_cash_flow_growth_score, all_data4))
    end

    test "10. ROA 全额计分：不再因ROE高分减半" do
      # 16% → 100；12% → 80；8% → 50；6% → 0
      assert_equal 100, StockPyramidService.send(:calculate_roa_score, (1..5).map { { roa: 16.0 } })
      assert_equal 80, StockPyramidService.send(:calculate_roa_score, (1..5).map { { roa: 12.0 } })
      assert_equal 50, StockPyramidService.send(:calculate_roa_score, (1..5).map { { roa: 8.0 } })
      assert_equal 0, StockPyramidService.send(:calculate_roa_score, (1..5).map { { roa: 6.0 } })
      # 不足3年 → 0
      assert_equal 0, StockPyramidService.send(:calculate_roa_score, [{ roa: 16.0 }, { roa: 16.0 }])
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

    test "12. 资产周转率：存储为「次」小数，均值>0.8得50分（边界锁定，防单位错配回归）" do
      # 0.81 = 81% → 得分；曾因阈值误写为 >80（百分制）导致全部A股此50分恒为0
      assert_equal 50, StockPyramidService.send(:calculate_asset_turnover_score, (1..5).map { { asset_turnover_ratio: 0.81 } })
      # 恰好 0.8 不得分（严格「超过」）
      assert_equal 0, StockPyramidService.send(:calculate_asset_turnover_score, (1..5).map { { asset_turnover_ratio: 0.8 } })
      assert_equal 0, StockPyramidService.send(:calculate_asset_turnover_score, (1..5).map { { asset_turnover_ratio: 0.79 } })
      # 不足5年不得分
      assert_equal 0, StockPyramidService.send(:calculate_asset_turnover_score, (1..4).map { { asset_turnover_ratio: 1.2 } })
    end

    test "13. 净利润规模：千亿/五百亿/百亿/盈利/亏损五档阶梯" do
      assert_equal 200, StockPyramidService.send(:calculate_net_income_score, (1..5).map { { net_income: 1000_0000_0000 } })
      assert_equal 150, StockPyramidService.send(:calculate_net_income_score, (1..5).map { { net_income: 500_0000_0000 } })
      assert_equal 100, StockPyramidService.send(:calculate_net_income_score, (1..5).map { { net_income: 100_0000_0000 } })
      assert_equal 50, StockPyramidService.send(:calculate_net_income_score, (1..5).map { { net_income: 20_0000_0000 } })
      assert_equal 0, StockPyramidService.send(:calculate_net_income_score, (1..5).map { { net_income: -1_0000_0000 } })
      # 不足5年不得分（与实现 size<5 口径一致）
      assert_equal 0, StockPyramidService.send(:calculate_net_income_score, (1..4).map { { net_income: 2000_0000_0000 } })
    end

    test "14. 毛利率扩容：水平分四档 + 稳定分按5年极差" do
      # 均值51% 极差0 → 60+40=100
      assert_equal 100, StockPyramidService.send(:calculate_gross_margin_score, (1..5).map { { gross_margin: 51.0 } })
      # 均值45% 极差0 → 45+40=85
      assert_equal 85, StockPyramidService.send(:calculate_gross_margin_score, (1..5).map { { gross_margin: 45.0 } })
      # 均值32% 极差8pp → 30+20=50
      assert_equal 50, StockPyramidService.send(:calculate_gross_margin_score, [28.0, 36.0, 30.0, 34.0, 32.0].map { |v| { gross_margin: v } })
      # 均值22% 极差0 → 15+40=55
      assert_equal 55, StockPyramidService.send(:calculate_gross_margin_score, (1..5).map { { gross_margin: 22.0 } })
      # 均值15% → 水平0+稳定40（稳定分不依赖水平分，与影子验证口径一致）
      assert_equal 40, StockPyramidService.send(:calculate_gross_margin_score, (1..5).map { { gross_margin: 15.0 } })
      # 不足5年 → 0
      assert_equal 0, StockPyramidService.send(:calculate_gross_margin_score, (1..4).map { { gross_margin: 60.0 } })
    end

    test "15. 净现比：OCF/净利均值 ≥1.0→60 / ≥0.8→30 / 其余0" do
      # 每年 OCF/NI = 1.2 → 60
      all_data1 = (1..5).map { { net_income: 100, operating_cash_flow: 120 } }
      assert_equal 60, StockPyramidService.send(:calculate_net_cash_ratio_score, all_data1)
      # 每年 0.9 → 30
      all_data2 = (1..5).map { { net_income: 100, operating_cash_flow: 90 } }
      assert_equal 30, StockPyramidService.send(:calculate_net_cash_ratio_score, all_data2)
      # 每年 0.7 → 0
      all_data3 = (1..5).map { { net_income: 100, operating_cash_flow: 70 } }
      assert_equal 0, StockPyramidService.send(:calculate_net_cash_ratio_score, all_data3)
      # 亏损年份（NI≤0）不参与统计：4个有效年均=1.0 → 60
      all_data4 = [{ net_income: -50, operating_cash_flow: 10 }] + (1..4).map { { net_income: 100, operating_cash_flow: 100 } }
      assert_equal 60, StockPyramidService.send(:calculate_net_cash_ratio_score, all_data4)
      # 有效年份恰好3 → 可计分
      all_data5 = [{ net_income: -50, operating_cash_flow: 10 }, { net_income: -30, operating_cash_flow: 5 }] +
                  (1..3).map { { net_income: 100, operating_cash_flow: 120 } }
      assert_equal 60, StockPyramidService.send(:calculate_net_cash_ratio_score, all_data5)
      # 有效年份不足3 → 0
      all_data6 = [{ net_income: -50, operating_cash_flow: 10 }, { net_income: -30, operating_cash_flow: 5 },
                   { net_income: -20, operating_cash_flow: 3 }] + (1..2).map { { net_income: 100, operating_cash_flow: 120 } }
      assert_equal 0, StockPyramidService.send(:calculate_net_cash_ratio_score, all_data6)
      # 单年比值封顶3.0（代码审查修复）：NI=0.1亿 OCF=30亿 原始比值300 → 截为3.0；
      # 均值 = (3.0 + 0.2×4)/5 = 0.76 < 0.8 → 0分（若不封顶均值≈60会错给满分60）
      capped = [{ net_income: 10_000_000, operating_cash_flow: 30_0000_0000 }] +
               (1..4).map { { net_income: 100, operating_cash_flow: 20 } }
      assert_equal 0, StockPyramidService.send(:calculate_net_cash_ratio_score, capped)
      # 封顶后仍达标的场景：3.0 + 1.0×4 → 均值1.4 → 60
      strong = [{ net_income: 10_000_000, operating_cash_flow: 30_0000_0000 }] +
               (1..4).map { { net_income: 100, operating_cash_flow: 100 } }
      assert_equal 60, StockPyramidService.send(:calculate_net_cash_ratio_score, strong)
    end
  end
end
