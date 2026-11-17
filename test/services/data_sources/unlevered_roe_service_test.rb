require "test_helper"

# 无杠杆ROE 纯函数计算引擎单测（口径B：分子加回税后净财务费用）
class UnleveredRoeServiceTest < ActiveSupport::TestCase
  S = DataSources::UnleveredRoeService

  # 万科式：亏损 + 高杠杆，税前为负 → 税率取0，利息全额加回
  def test_loss_company_adds_back_full_interest
    r = S.compute(ttm_np: -400, ttm_fin_exp: 60, ttm_tax: 10, ttm_pretax: -50,
                  parent_equity: 930, interest_debt: 1750)
    assert_equal S::FLAG_NORMAL, r[:flag]
    # 税前为负 → 税率取0，利息全额加回：(-400 + 60) / (930 + 1750) * 100 = -12.6866...
    assert_in_delta(-12.69, r[:value], 0.01)
  end

  # 口径B核心性质：经营回报相同的杠杆/无杠杆公司，值应一致
  # U: 权益100 无债，EBIT10 税25% → 净利7.5；L: 权益50 债50@5% → 净利5.625，利息2.5
  def test_leverage_neutral_comparison
    u = S.compute(ttm_np: 7.5, ttm_fin_exp: 0, ttm_tax: 2.5, ttm_pretax: 10,
                  parent_equity: 100, interest_debt: 0)
    l = S.compute(ttm_np: 5.625, ttm_fin_exp: 2.5, ttm_tax: 1.875, ttm_pretax: 7.5,
                  parent_equity: 50, interest_debt: 50)
    assert_in_delta(u[:value], l[:value], 0.01)
    assert_in_delta(7.5, u[:value], 0.01)
  end

  # 茅台式：有息负债科目全空 → 债务按0，值≈普通ROE（期末口径）
  def test_no_debt_falls_back_to_equity_only
    r = S.compute(ttm_np: 500, ttm_fin_exp: nil, ttm_tax: nil, ttm_pretax: nil,
                  parent_equity: 2000, interest_debt: nil)
    assert_equal S::FLAG_NORMAL, r[:flag]
    assert_in_delta(25.0, r[:value], 0.01)
  end

  def test_financial_stock_flagged
    r = S.compute(ttm_np: 100, ttm_fin_exp: 0, ttm_tax: 0, ttm_pretax: 100,
                  parent_equity: 1000, interest_debt: 0, financial_stock: true)
    assert_nil r[:value]
    assert_equal S::FLAG_FINANCIAL, r[:flag]
  end

  def test_missing_profit_or_equity_flagged_not_disclosed
    r = S.compute(ttm_np: nil, ttm_fin_exp: 1, ttm_tax: 1, ttm_pretax: 1,
                  parent_equity: 100, interest_debt: 0)
    assert_equal S::FLAG_NOT_DISCLOSED, r[:flag]

    # 历史期次未重爬新科目（parent_equity 列为 NULL）同样落 flag 1
    r2 = S.compute(ttm_np: 100, ttm_fin_exp: 1, ttm_tax: 1, ttm_pretax: 1,
                   parent_equity: nil, interest_debt: 50)
    assert_equal S::FLAG_NOT_DISCLOSED, r2[:flag]
  end

  def test_non_positive_equity_flagged
    r = S.compute(ttm_np: -100, ttm_fin_exp: 10, ttm_tax: 0, ttm_pretax: -90,
                  parent_equity: 0, interest_debt: 100)
    assert_equal S::FLAG_NEGATIVE_EQUITY, r[:flag]
  end

  # 净财务费用为负（利息收入>支出，现金充裕公司）→ 加回项为负，方向自洽
  def test_negative_financial_expense_reduces_numerator
    r = S.compute(ttm_np: 100, ttm_fin_exp: -20, ttm_tax: 25, ttm_pretax: 125,
                  parent_equity: 500, interest_debt: 0)
    # (100 + (-20)×0.8) / 500 × 100 = 16.8
    assert_in_delta(16.8, r[:value], 0.01)
  end

  # 异常税率（税>税前）→ 税率取0全额加回，不产生负抵税放大
  def test_abnormal_tax_rate_guard
    r = S.compute(ttm_np: 100, ttm_fin_exp: 40, ttm_tax: 200, ttm_pretax: 100,
                  parent_equity: 600, interest_debt: 400)
    # (100 + 40) / 1000 × 100 = 14.0
    assert_in_delta(14.0, r[:value], 0.01)
  end

  def test_reference_roe_returned_for_alarm
    r = S.compute(ttm_np: 100, ttm_fin_exp: 40, ttm_tax: 25, ttm_pretax: 133.33,
                  parent_equity: 500, interest_debt: 500)
    assert_in_delta(20.0, r[:reference_roe], 0.01)
  end

  # 金融股判定：sector=银行 或 industry 含 银行/证券/保险
  def test_financial_stock_detection
    bank = Stock.new(sector: "银行", industry: "银行")
    broker = Stock.new(sector: "非银金融", industry: "证券")
    insurer = Stock.new(sector: "非银金融", industry: "保险")
    realestate = Stock.new(sector: "房地产", industry: "房地产开发")

    assert S.financial_stock?(bank)
    assert S.financial_stock?(broker)
    assert S.financial_stock?(insurer)
    assert_not S.financial_stock?(realestate)
  end

  # 美股金融股：银行/保险/资本市场/资管/金融综合/壳公司剔除；
  # 信用服务（V/MA）与金融数据/交易所保留
  def test_us_financial_stock_detection
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "多元化银行"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "寿险"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "资本市场"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "资产管理"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "金融综合集团"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "抵押金融"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "金融服务", industry: "壳公司"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "医疗保健", industry: "医保计划"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "房地产", industry: "抵押REIT"), market: "US")

    assert_not S.financial_stock?(Stock.new(sector: "金融服务", industry: "信用服务"), market: "US")
    assert_not S.financial_stock?(Stock.new(sector: "金融服务", industry: "金融数据与交易所"), market: "US")
    assert_not S.financial_stock?(Stock.new(sector: "科技", industry: "消费电子"), market: "US")

    # 英文兜底（行业映射失败时）
    assert S.financial_stock?(Stock.new(sector: "Financial Services", industry: "Banks—Diversified"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "Healthcare", industry: "Healthcare Plans"), market: "US")
    assert S.financial_stock?(Stock.new(sector: "Real Estate", industry: "Mortgage REIT"), market: "US")

    # 加密矿企虽被 Yahoo 归入「资本市场」，但属经营型公司，不按金融股剔除
    assert_not S.financial_stock?(Stock.new(symbol: "HUT", sector: "金融服务", industry: "资本市场"), market: "US")
    assert S.financial_stock?(Stock.new(symbol: "GS", sector: "金融服务", industry: "资本市场"), market: "US")
  end

  # 美股「利息支出」为负数毛额：净利息 = |支出| − |收入|；A股财务费用已净额，不归一化
  def test_us_interest_value_normalizes_sign_and_subtracts_income
    ko = IncomeStatement.new(interest_expense: -1_654, interest_income: 786)
    assert_equal BigDecimal("868"), S.send(:interest_value, ko, "US") # 净利息费用 868

    t = IncomeStatement.new(interest_expense: -6_804, interest_income: nil)
    assert_equal BigDecimal("6804"), S.send(:interest_value, t, "US")

    none = IncomeStatement.new(interest_expense: nil, interest_income: nil)
    assert_nil S.send(:interest_value, none, "US")

    cn = IncomeStatement.new(interest_expense: -20)
    assert_equal BigDecimal("-20"), S.send(:interest_value, cn, "CN")
  end

  # 美股有有息负债但利息费用未披露 → 值照算、flag 4；无负债则不标
  def test_us_missing_interest_flags_only_when_debt_present
    assert S.send(:interest_missing?, "US", true, 100)
    assert_not S.send(:interest_missing?, "US", true, 0)
    assert_not S.send(:interest_missing?, "CN", true, 100)

    r = S.compute(ttm_np: 100, ttm_fin_exp: nil, ttm_tax: nil, ttm_pretax: nil,
                  parent_equity: 500, interest_debt: 500, interest_missing: true)
    assert_equal S::FLAG_INTEREST_MISSING, r[:flag]
    assert_in_delta 10.0, r[:value], 0.01
    assert_in_delta 20.0, r[:reference_roe], 0.01
  end

  # 美股只有利息收入、没有利息支出且有有息负债：必须 0 加回 + flag 4，
  # 不能扣减利息收入（META 2025 年报场景）
  def test_us_missing_interest_expense_with_income_zeroes_addback
    report_date = Date.new(2025, 12, 31)
    indicator = FinancialIndicator.new(report_date: report_date, period_type: "annual")
    incomes = {
      report_date => IncomeStatement.new(
        report_date: report_date, period_type: "annual",
        net_income_to_shareholders: 60_000, interest_expense: nil, interest_income: 2_656,
        income_tax: 10_000, income_before_tax: 70_000
      )
    }
    balances = {
      report_date => BalanceSheet.new(
        report_date: report_date, period_type: "annual",
        parent_equity: 217_243, long_term_debt: 83_897
      )
    }

    r = S.send(:compute_period, indicator, incomes, balances, false, "US", false, false)

    assert_equal S::FLAG_INTEREST_MISSING, r[:flag]
    # 0 加回：60000 ÷ (217243 + 83897) × 100 = 19.92
    assert_in_delta 19.92, r[:value], 0.01
  end

  # REIT 债务数据完整性：debt/TL < 50% 且有利息费用 → flag 5 隐藏；
  # 债务拆分完整（AMT/PLD/SPG 约 85%）或明确无利息的 REIT 不标记
  def test_us_reit_debt_incomplete_is_hidden
    incomplete = BalanceSheet.new(total_liabilities: 25_960, long_term_debt: 5_113)
    gray = BalanceSheet.new(total_liabilities: 5_190, long_term_debt: 1_790)
    assert S.send(:reit_debt_incomplete?, true, incomplete, BigDecimal("100"))
    assert S.send(:reit_debt_incomplete?, true, gray, BigDecimal("100")), "34.5% 灰区也应判定为不完整"
    assert_not S.send(:reit_debt_incomplete?, true, incomplete, BigDecimal(0))
    assert_not S.send(:reit_debt_incomplete?, false, incomplete, BigDecimal("100"))

    complete = BalanceSheet.new(total_liabilities: 52_840, long_term_debt: 44_960)
    assert_not S.send(:reit_debt_incomplete?, true, complete, BigDecimal("100"))

    r = S.compute(ttm_np: 100, ttm_fin_exp: 10, ttm_tax: 10, ttm_pretax: 110,
                  parent_equity: 14_160, interest_debt: 5_113, debt_incomplete: true)
    assert_nil r[:value]
    assert_equal S::FLAG_DEBT_INCOMPLETE, r[:flag]
  end

  # 非 REIT 通用债务缺口：debt=0、TL>2×权益、TL>5B、利息缺失/0 → flag 5；
  # 小额真无债务（DNN 0.74B）或 TL 未超 2×权益不标记
  def test_us_generic_debt_gap_is_hidden
    veon = BalanceSheet.new(total_liabilities: 7_580_000_000, parent_equity: 1_340_000_000)
    assert S.send(:generic_debt_incomplete?, "US", veon, BigDecimal(0), true, nil)
    assert S.send(:generic_debt_incomplete?, "US", veon, BigDecimal(0), false, BigDecimal("100"))
    assert_not S.send(:generic_debt_incomplete?, "US", veon, BigDecimal(0), false, BigDecimal(0))
    assert_not S.send(:generic_debt_incomplete?, "US", veon, BigDecimal("100"), true, nil)
    assert_not S.send(:generic_debt_incomplete?, "CN", veon, BigDecimal(0), true, nil)

    dnn = BalanceSheet.new(total_liabilities: 740_000_000, parent_equity: 370_000_000)
    assert_not S.send(:generic_debt_incomplete?, "US", dnn, BigDecimal(0), true, nil)

    low = BalanceSheet.new(total_liabilities: 9_000_000_000, parent_equity: 6_000_000_000)
    assert_not S.send(:generic_debt_incomplete?, "US", low, BigDecimal(0), true, nil)
  end

  # 信用服务放贷机构：有巨额利息收入、利息支出缺失、有息负债=0，
  # 不能被当成“负加回”算出 -45% 之类的值，应落 flag5
  def test_us_lender_with_interest_income_and_no_debt_is_hidden
    report_date = Date.new(2025, 12, 31)
    indicator = FinancialIndicator.new(report_date: report_date, period_type: "annual")
    incomes = {
      report_date => IncomeStatement.new(
        report_date: report_date, period_type: "annual",
        net_income_to_shareholders: 2_180_000_000, interest_expense: nil,
        interest_income: 58_700_000_000, income_tax: 500_000_000, income_before_tax: 2_700_000_000
      )
    }
    balances = {
      report_date => BalanceSheet.new(
        report_date: report_date, period_type: "annual",
        parent_equity: 113_620_000_000, total_liabilities: 555_390_000_000
      )
    }

    r = S.send(:compute_period, indicator, incomes, balances, false, "US", false, false)

    assert_equal S::FLAG_DEBT_INCOMPLETE, r[:flag]
    assert_nil r[:value]
  end

  # 部分债务缺口：利息费用/有息负债 > 20% 且总负债 > 1B → flag5
  def test_us_implied_rate_gap_is_hidden
    run = BalanceSheet.new(total_liabilities: 17_630_000_000, parent_equity: 3_130_000_000,
                           long_term_debt: 330_000_000)
    assert S.send(:implied_rate_gap?, "US", run, BigDecimal("330000000"), BigDecimal("1000000000"))
    assert_not S.send(:implied_rate_gap?, "US", run, BigDecimal("10000000000"), BigDecimal("500000000"))
    assert_not S.send(:implied_rate_gap?, "CN", run, BigDecimal("330000000"), BigDecimal("1000000000"))

    small = BalanceSheet.new(total_liabilities: 900_000_000, parent_equity: 300_000_000,
                             long_term_debt: 10_000_000)
    assert_not S.send(:implied_rate_gap?, "US", small, BigDecimal("10000000"), BigDecimal("100000000"))
  end

  def test_us_generic_debt_gap_flows_through_compute_period
    report_date = Date.new(2025, 12, 31)
    indicator = FinancialIndicator.new(report_date: report_date, period_type: "annual")
    incomes = {
      report_date => IncomeStatement.new(
        report_date: report_date, period_type: "annual",
        net_income_to_shareholders: 1_000, interest_expense: nil,
        income_tax: 100, income_before_tax: 1_400
      )
    }
    balances = {
      report_date => BalanceSheet.new(
        report_date: report_date, period_type: "annual",
        parent_equity: 1_340_000_000, total_liabilities: 7_580_000_000
      )
    }

    r = S.send(:compute_period, indicator, incomes, balances, false, "US", false, false)

    assert_equal S::FLAG_DEBT_INCOMPLETE, r[:flag]
    assert_nil r[:value]
  end

  # 信用服务放贷机构：debt=0、利息支出缺失、TL>5B，即使 TL/权益<2× 也隐藏（AFRM 1.88×）
  def test_us_credit_service_debt_gap_is_hidden
    afrm = BalanceSheet.new(total_liabilities: 10_310_000_000, parent_equity: 5_480_000_000)
    assert S.send(:credit_service_debt_gap?, "US", true, afrm, BigDecimal(0), true)
    assert_not S.send(:credit_service_debt_gap?, "US", true, afrm, BigDecimal("100"), true)
    assert_not S.send(:credit_service_debt_gap?, "US", false, afrm, BigDecimal(0), true)
    assert_not S.send(:credit_service_debt_gap?, "US", true, afrm, BigDecimal(0), false)

    small = BalanceSheet.new(total_liabilities: 4_000_000_000, parent_equity: 2_000_000_000)
    assert_not S.send(:credit_service_debt_gap?, "US", true, small, BigDecimal(0), true)
  end

  def test_us_credit_service_debt_gap_flows_through_compute_period
    report_date = Date.new(2026, 6, 30)
    indicator = FinancialIndicator.new(report_date: report_date, period_type: "annual")
    incomes = {
      report_date => IncomeStatement.new(
        report_date: report_date, period_type: "annual",
        net_income_to_shareholders: 1_900_000_000, interest_expense: nil,
        income_tax: 100_000_000, income_before_tax: 2_000_000_000
      )
    }
    balances = {
      report_date => BalanceSheet.new(
        report_date: report_date, period_type: "annual",
        parent_equity: 5_480_000_000, total_liabilities: 10_310_000_000
      )
    }

    r = S.send(:compute_period, indicator, incomes, balances, false, "US", false, true)

    assert_equal S::FLAG_DEBT_INCOMPLETE, r[:flag]
    assert_nil r[:value]
  end

  def test_us_reit_incomplete_debt_flows_through_compute_period
    report_date = Date.new(2025, 12, 31)
    indicator = FinancialIndicator.new(report_date: report_date, period_type: "annual")
    incomes = {
      report_date => IncomeStatement.new(
        report_date: report_date, period_type: "annual",
        net_income_to_shareholders: 1_000, interest_expense: -500,
        income_tax: 100, income_before_tax: 1_400
      )
    }
    balances = {
      report_date => BalanceSheet.new(
        report_date: report_date, period_type: "annual",
        parent_equity: 14_160, long_term_debt: 5_113, total_liabilities: 25_960
      )
    }

    r = S.send(:compute_period, indicator, incomes, balances, false, "US", true, false)

    assert_equal S::FLAG_DEBT_INCOMPLETE, r[:flag]
    assert_nil r[:value]
  end

  # 美股财年非 12-31：上年年报取本期之前最近一期；
  # 52/53 周财年的上年同期日期会漂移（2025-06-28 vs 目标 2025-06-27），用 ±20 天容差匹配
  def test_us_ttm_stitches_fiscal_calendar_with_tolerance
    incomes = [
      IncomeStatement.new(report_date: Date.new(2026, 6, 27), period_type: "q3",
                          net_income_to_shareholders: 101_464, interest_expense: nil,
                          interest_income: nil, income_tax: 21_638, income_before_tax: 123_102),
      IncomeStatement.new(report_date: Date.new(2025, 9, 27), period_type: "annual",
                          net_income_to_shareholders: 112_010, interest_expense: nil,
                          interest_income: nil, income_tax: 20_719, income_before_tax: 132_729),
      IncomeStatement.new(report_date: Date.new(2025, 6, 28), period_type: "q3",
                          net_income_to_shareholders: 84_544, interest_expense: nil,
                          interest_income: nil, income_tax: 15_381, income_before_tax: 99_925)
    ].index_by(&:report_date)
    indicator = FinancialIndicator.new(report_date: Date.new(2026, 6, 27), period_type: "q3")

    ttm = S.send(:ttm_items, indicator, incomes, "US")
    assert_equal 128_930, ttm[:ttm_np]  # 101464 + 112010 - 84544
    assert_nil ttm[:ttm_fin_exp]
    assert_equal 26_976, ttm[:ttm_tax]   # 21638 + 20719 - 15381
    assert_equal 155_906, ttm[:ttm_pretax] # 123102 + 132729 - 99925
  end

  # A股 TTM 行为保持不变：上年年报锚定 12-31，上年同期精确 -1 年
  def test_cn_ttm_keeps_december_annual_anchor
    incomes = [
      IncomeStatement.new(report_date: Date.new(2025, 9, 30), period_type: "q3",
                          net_income_to_shareholders: 90, interest_expense: 5,
                          income_tax: 5, income_before_tax: 40),
      IncomeStatement.new(report_date: Date.new(2024, 12, 31), period_type: "annual",
                          net_income_to_shareholders: 100, interest_expense: 6,
                          income_tax: 6, income_before_tax: 45),
      IncomeStatement.new(report_date: Date.new(2024, 9, 30), period_type: "q3",
                          net_income_to_shareholders: 80, interest_expense: 4,
                          income_tax: 4, income_before_tax: 35)
    ].index_by(&:report_date)
    indicator = FinancialIndicator.new(report_date: Date.new(2025, 9, 30), period_type: "q3")

    ttm = S.send(:ttm_items, indicator, incomes, "CN")
    assert_equal 110, ttm[:ttm_np]
    assert_equal BigDecimal("7"), ttm[:ttm_fin_exp]
    assert_equal BigDecimal("7"), ttm[:ttm_tax]
    assert_equal BigDecimal("50"), ttm[:ttm_pretax]
  end
end
