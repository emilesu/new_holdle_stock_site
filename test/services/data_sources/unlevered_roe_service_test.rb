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
end
