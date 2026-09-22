require "test_helper"

# 股票筛选服务单测：不依赖共享 fixture，数据在测试内自建（事务回滚）
class StockScreenerServiceTest < ActiveSupport::TestCase
  # 三只 A 股：
  #   GOOD  2021-2023 每年 ROE≥25、毛利率≥45、净利率≥12，净利润逐年上升
  #   MIX   2021 ROE=10、2022 ROE=30、2023 ROE=30（仅部分年达标），净利润有回落
  #   GAP   2021、2023 ROE=30，缺 2022 年报（all 模式应排除）
  def setup
    @good = create_stock("GOOD", score: 300)
    @mix  = create_stock("MIX", score: 200)
    @gap  = create_stock("GAP", score: 100)

    add_annual(@good, 2021, roe: 25, gm: 45, npm: 12, ni: 100)
    add_annual(@good, 2022, roe: 28, gm: 48, npm: 14, ni: 130)
    add_annual(@good, 2023, roe: 30, gm: 50, npm: 15, ni: 180)

    add_annual(@mix, 2021, roe: 10, gm: 30, npm: 5, ni: 100)
    add_annual(@mix, 2022, roe: 30, gm: 35, npm: 8, ni: 90)   # 回落
    add_annual(@mix, 2023, roe: 30, gm: 36, npm: 9, ni: 120)

    add_annual(@gap, 2021, roe: 30, gm: 50, npm: 20, ni: 50)
    add_annual(@gap, 2023, roe: 30, gm: 52, npm: 21, ni: 80)
  end

  # ---------- 盈利指标三口径 ----------

  test "all 模式：区间内每个年度均达标才命中，缺年报股票排除" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "all", roe_value: "20")
    assert result.ok?, result.errors.join("；")
    assert_equal [@good.id], result.stocks.map(&:id)
  end

  test "any 模式：区间内至少一年达标即命中" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "any", roe_value: "20")
    assert_equal [@good, @mix, @gap].map(&:id).sort, result.stocks.map(&:id).sort
  end

  test "last 模式：仅看末年" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "last", roe_value: "20")
    assert_equal [@good, @mix, @gap].map(&:id).sort, result.stocks.map(&:id).sort

    result2 = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "last", roe_value: "29")
    assert_equal [@good, @mix, @gap].map(&:id).sort, result2.stocks.map(&:id).sort

    result3 = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "last", roe_value: "31")
    assert_empty result3.stocks
  end

  test "lte 方向：末年 ROE ≤ 15 命中 MIX 首年之外？仅末年仅 MIX 不满足，GOOD/GAP 不满足" do
    # MIX 末年 ROE=30；用区间 2021-2021 末年=2021，MIX ROE=10 命中
    result = screen(market: "CN", year_from: 2021, year_to: 2021, margin_mode: "last", roe_op: "lte", roe_value: "15")
    assert_equal [@mix.id], result.stocks.map(&:id)
  end

  test "多指标 AND 组合：ROE≥20 且 毛利率≥45（all 模式）" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "all",
                    roe_value: "20", gm_value: "45")
    assert_equal [@good.id], result.stocks.map(&:id)
  end

  # ---------- 净利润增长 ----------

  test "yoy 模式：末年同比增长达阈值命中，回落不命中" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, growth_mode: "yoy", growth_value: "30")
    # GOOD 2023/2022 = 180/130 ≈ 38.5% 命中；MIX 120/90 ≈ 33.3% 命中；GAP 80/50=60% 但缺 2022 年报 → 无上年行，排除
    assert_equal [@good.id, @mix.id].sort, result.stocks.map(&:id).sort
  end

  test "yoy 模式：上年净利润为正才参与计算" do
    neg = create_stock("NEG")
    add_annual(neg, 2022, ni: -50)
    add_annual(neg, 2023, ni: 100)
    result = screen(market: "CN", year_from: 2022, year_to: 2023, growth_mode: "yoy", growth_value: "0")
    refute_includes result.stocks.map(&:id), neg.id
  end

  test "always_up 模式：区间内逐年上升，中途回落/缺年报不命中" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, growth_mode: "always_up")
    assert_equal [@good.id], result.stocks.map(&:id)
  end

  # ---------- 条件叠加与展示指标 ----------

  test "盈利 + 增长条件叠加取交集" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "all", roe_value: "20",
                    growth_mode: "always_up")
    assert_equal [@good.id], result.stocks.map(&:id)
  end

  test "metrics 带出区间最低/末年 ROE、末年毛利率净利率与净利润同比" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "all", roe_value: "20")
    m = result.metrics[@good.id]
    assert_in_delta 25, m[:roe_min], 0.01
    assert_in_delta 30, m[:roe_last], 0.01
    assert_in_delta 50, m[:gm_last], 0.01
    assert_in_delta 15, m[:npm_last], 0.01
    assert_in_delta 38.46, m[:ni_growth], 0.1
  end

  # ---------- 排序与分页 ----------

  test "默认按金字塔分降序" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "any", roe_value: "20")
    assert_equal [@good, @mix, @gap].map(&:id), result.stocks.map(&:id)
  end

  test "roe_min 排序：区间最低 ROE 降序" do
    # GOOD 最低 25，GAP 最低 30（仅 2021/2023 两年），MIX 最低 10
    result = screen(market: "CN", year_from: 2021, year_to: 2023, margin_mode: "any", roe_value: "20", sort: "roe_min")
    assert_equal [@gap, @good, @mix].map(&:id), result.stocks.map(&:id)
  end

  test "分页：总数与页数正确，超界页码钳制到末页" do
    21.upto(28) do |i|
      s = create_stock("P#{i}", score: i)
      add_annual(s, 2023, roe: 40)
    end
    result = screen(market: "CN", year_from: 2023, year_to: 2023, margin_mode: "last", roe_value: "20", page: 2)
    assert_equal 11, result.total_count # GOOD/MIX/GAP + 8 只新建
    assert_equal 1, result.total_pages   # 11 <= PER_PAGE(20)
    assert_equal 1, result.page          # 越界钳制到末页
    assert_equal 11, result.stocks.size
  end

  # ---------- 参数校验与安全 ----------

  test "无效市场被拒绝" do
    result = screen(market: "JP", roe_value: "20")
    refute result.ok?
  end

  test "年度区间倒挂被拒绝" do
    result = screen(market: "CN", year_from: 2023, year_to: 2021, roe_value: "20")
    refute result.ok?
  end

  test "无任何条件被拒绝" do
    result = screen(market: "CN")
    refute result.ok?
  end

  test "非枚举模式参数被拒绝" do
    result = screen(market: "CN", roe_value: "20", margin_mode: "drop_table")
    refute result.ok?
  end

  test "校验失败时 conditions 回显原始输入供表单保留" do
    result = screen(market: "CN", year_from: 2023, year_to: 2021, roe_value: "20", gm_value: "45")
    refute result.ok?
    assert_equal 2023, result.conditions[:year_from]
    assert_equal 2021, result.conditions[:year_to]
    assert_equal %w[roe gm], result.conditions[:margin_conditions].map { |x| x[:key] }
  end

  test "SQL 注入字符串作为普通值处理，不破坏数据" do
    result = screen(market: "CN", year_from: 2021, year_to: 2023,
                    margin_mode: "all", roe_value: "20", sector: "'; DROP TABLE stocks; --")
    assert result.ok?
    assert_empty result.stocks
    assert Stock.exists?(@good.id)
  end

  test "退市股票不参与筛选" do
    delisted = create_stock("DELISTED", status: "delisted")
    add_annual(delisted, 2023, roe: 99)
    result = screen(market: "CN", year_from: 2023, year_to: 2023, margin_mode: "last", roe_value: "20")
    refute_includes result.stocks.map(&:id), delisted.id
  end

  test "其他市场股票不串入结果" do
    us = create_stock("USX", market: "US")
    add_annual(us, 2023, roe: 99)
    result = screen(market: "CN", year_from: 2023, year_to: 2023, margin_mode: "last", roe_value: "20")
    refute_includes result.stocks.map(&:id), us.id
  end

  private

  def screen(params)
    StockScreenerService.call(params.symbolize_keys)
  end

  def create_stock(symbol, market: "CN", sector: "测试板块", status: "listed", score: 0)
    Stock.create!(symbol: symbol, name: "测试#{symbol}", market: market, sector: sector,
                  exchange: "SSE", status: status, pyramid_total_score: score)
  end

  def add_annual(stock, year, roe: nil, gm: nil, npm: nil, ni: nil)
    rd = Date.new(year, 12, 31)
    report = FinancialReport.create!(stock: stock, report_date: rd, market: stock.market,
                                     report_type: "年报", period_type: "annual")
    FinancialIndicator.create!(financial_report: report, stock: stock, report_date: rd,
                               market: stock.market, period_type: "annual",
                               roe_avg: roe, gross_margin: gm, net_sales_rate: npm)
    IncomeStatement.create!(financial_report: report, stock: stock, report_date: rd,
                            market: stock.market, period_type: "annual",
                            net_income_to_shareholders: ni)
  end
end
