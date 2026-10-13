require "test_helper"

# 企业质量档案只读接口：鉴权 / code 归一化 / 派生字段归母口径 / peers 排序
class Api::V1::ArchiveControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["HOLDLE_ARCHIVE_TOKEN"] = "archive-test-token"
    @auth = { "Authorization" => "Bearer archive-test-token" }
  end

  # 构造 A 股 + 一期年报（四子表齐），返回 [stock, indicator]
  # calc_at 传入即视为「已重算」，ranking 榜单只收 last_pyramid_calc_at 非空的标的
  def create_cn_stock_with_annual(symbol:, name:, score:, sector: "医药生物", industry: "医疗服务",
                                  year: 2025, revenue: nil, parent: nil, calc_at: nil, **indicator_attrs)
    stock = Stock.create!(symbol: symbol, name: name, market: "CN", sector: sector, industry: industry,
                          exchange: "SHSE", status: "active", pyramid_total_score: score,
                          last_pyramid_calc_at: calc_at)
    report_date = Date.new(year, 12, 31)
    fr = FinancialReport.create!(stock: stock, report_date: report_date, report_type: "CN_ANNUAL",
                                 market: "CN", period_type: "annual", currency: "CNY")
    if revenue || parent
      IncomeStatement.create!(financial_report: fr, stock: stock, report_date: report_date, market: "CN",
                              period_type: "annual", total_revenue: revenue,
                              net_income_to_shareholders: parent)
    end
    FinancialIndicator.create!(financial_report: fr, stock: stock, report_date: report_date, market: "CN",
                               period_type: "annual", **indicator_attrs)
    [stock, fr]
  end

  test "无 token 返回 401" do
    get "/api/v1/archive/pyramid?code=SH603259"
    assert_response 401
    assert_equal false, response.parsed_body["success"]
  end

  test "错误 token 返回 401" do
    get "/api/v1/archive/financials?code=SH603259", headers: { "Authorization" => "Bearer wrong" }
    assert_response 401
  end

  test "未知 code 返回 404" do
    get "/api/v1/archive/pyramid?code=999999.SH", headers: @auth
    assert_response 404
  end

  test "pyramid 支持后缀式 code 并返回两级 peers 与名次" do
    create_cn_stock_with_annual(symbol: "SH600519", name: "贵州茅台", score: 900)
    stock, = create_cn_stock_with_annual(symbol: "SH603259", name: "药明康德", score: 800)
    create_cn_stock_with_annual(symbol: "SH300750", name: "宁德时代", score: 700,
                                sector: "电力设备", industry: "电池")

    get "/api/v1/archive/pyramid?code=603259.SH", headers: @auth
    assert_response 200
    data = response.parsed_body["data"]

    assert_equal "603259.SH", data["code"]
    assert_equal "医药生物", data["sw_l1"]
    assert_equal "医疗服务", data["sw_l2"]
    assert_equal "主板", data["board"]
    assert_equal 800, data["pyramid_score"]
    assert_equal "2025年报", data["data_period"]

    # 一级行业（医药生物）榜含茅台+药明；二级同；电池股不在列
    assert_equal %w[600519.SH 603259.SH], data["peers"]["sw_l1_top"].map { |p| p["code"] }
    assert_equal [1, 2], data["peers"]["sw_l2_top"].map { |p| p["rank"] }
    assert_equal 2, data["peers"]["rank_in_sw_l2"]
  end

  test "pyramid 前缀式 code 大小写不敏感" do
    create_cn_stock_with_annual(symbol: "SH603259", name: "药明康德", score: 800)

    get "/api/v1/archive/pyramid?code=sh603259", headers: @auth
    assert_response 200
    assert_equal "603259.SH", response.parsed_body["data"]["code"]

    get "/api/v1/archive/financials?code=sz300750", headers: @auth
    assert_response 404  # 未入库股票仍应 404，不因归一化误命中
  end

  test "financials 归母口径派生字段与药明 2025 年报验收值一致" do
    _stock, fr = create_cn_stock_with_annual(
      symbol: "SH603259", name: "药明康德", score: 800,
      revenue: 45_456_165_774.18, parent: 19_150_582_400.69,
      roe_avg: 28.56, deducted_net_profit: 13_240_556_954.42,
      deducted_roe_weighted: 19.74, disclosed_at: Date.new(2026, 3, 23),
      basic_eps: 6.6, diluted_eps: 6.42, eps_diluted: 6.55
    )
    report_date = fr.report_date
    BalanceSheet.create!(financial_report: fr, stock: fr.stock, report_date: report_date, market: "CN",
                         period_type: "annual", total_assets: 103_120_968_579.11,
                         cash_and_cash_equivalents: 35_131_309_638.47)
    CashFlow.create!(financial_report: fr, stock: fr.stock, report_date: report_date, market: "CN",
                     period_type: "annual", operating_cash_flow: 17_203_161_622.00)

    get "/api/v1/archive/financials?code=603259.SH&period=2025", headers: @auth
    assert_response 200
    data = response.parsed_body["data"]
    fields = data["fields"]

    assert_equal "2025年报", data["period"]
    assert_equal "2026-03-23", data["disclosed_at"]
    assert_in_delta 45_456_165_774.18, fields["revenue"]["value"].to_f, 0.01
    assert_in_delta 42.13, fields["parent_net_margin"]["value"].to_f, 0.001
    assert_in_delta 5_910_025_446.27, fields["non_recurring_net"]["value"].to_f, 0.01
    assert_in_delta 34.07, fields["cash_ratio"]["value"].to_f, 0.001
    assert_in_delta 17_203_161_622.00, fields["op_cashflow"]["value"].to_f, 0.01
    assert_in_delta 19.74, fields["deducted_roe_weighted"]["value"].to_f, 0.001

    # 归母口径自洽：margin 与 parent/revenue 误差 ≤0.01pp
    margin = fields["parent_net_margin"]["value"].to_f
    raw = fields["parent_net_profit"]["value"].to_f / fields["revenue"]["value"].to_f * 100
    assert_operator (margin - raw).abs, :<=, 0.01

    # EPS 语义纠正：eps_deducted=库内扣非值，eps_diluted=新列真实稀释值
    assert_in_delta 6.42, fields["eps_deducted"]["value"].to_f, 0.001
    assert_in_delta 6.55, fields["eps_diluted"]["value"].to_f, 0.001

    # history 含该期
    entry = data["history"].find { |h| h["period"] == "2025年报" }
    assert_not_nil entry
    assert_in_delta 28.56, entry["roe_weighted"].to_f, 0.001
  end

  test "扣非未回填时返回 null 且标注待回填" do
    create_cn_stock_with_annual(symbol: "SH600000", name: "浦发银行", score: 500,
                                revenue: 100.0, parent: 50.0)

    get "/api/v1/archive/financials?code=SH600000", headers: @auth
    assert_response 200
    deducted = response.parsed_body["data"]["fields"]["deducted_net_profit"]
    assert_nil deducted["value"]
    assert_equal "源未提供/待回填", deducted["caliber"]
  end

  test "请求不存在的期次返回 404" do
    create_cn_stock_with_annual(symbol: "SH600001", name: "测试股", score: 100)

    get "/api/v1/archive/financials?code=SH600001&period=2019", headers: @auth
    assert_response 404
  end

  # ---------- ranking 榜单（契约 23_Trae榜单接口需求_20261013.md） ----------

  test "ranking 无 token 返回 401" do
    get "/api/v1/archive/ranking"
    assert_response 401
  end

  test "ranking 本期仅支持 cn，其他市场 400" do
    get "/api/v1/archive/ranking?market=hk", headers: @auth
    assert_response 400

    get "/api/v1/archive/ranking?market=CN", headers: @auth
    assert_response 200
  end

  test "ranking 排除未计算标的并按 score DESC、id DESC 稳定排序" do
    calc = Time.zone.parse("2026-10-01 10:00:00")
    create_cn_stock_with_annual(symbol: "SH600519", name: "贵州茅台", score: 900, calc_at: calc)
    create_cn_stock_with_annual(symbol: "SZ300001", name: "并列先", score: 800, calc_at: calc)
    create_cn_stock_with_annual(symbol: "SZ300002", name: "并列后", score: 800, calc_at: calc)
    create_cn_stock_with_annual(symbol: "SH600000", name: "未计算", score: 999)  # calc_at 为 nil，不入榜

    get "/api/v1/archive/ranking", headers: @auth
    assert_response 200
    data = response.parsed_body["data"]

    assert_equal 3, data["total"]
    assert_equal %w[600519.SH 300002.SZ 300001.SZ], data["items"].map { |i| i["code"] }
    assert_equal [1, 2, 3], data["items"].map { |i| i["rank"] }
    assert_equal calc.in_time_zone.iso8601, data["snapshot_at"]
  end

  test "ranking 榜首与 pyramid 单只接口逐值一致（同源验收）" do
    calc = Time.zone.parse("2026-10-02 08:30:00")
    create_cn_stock_with_annual(symbol: "SH688617", name: "惠泰医疗", score: 875, calc_at: calc)

    get "/api/v1/archive/ranking?limit=1", headers: @auth
    item = response.parsed_body["data"]["items"].first

    get "/api/v1/archive/pyramid?code=688617.SH", headers: @auth
    single = response.parsed_body["data"]

    assert_equal single["pyramid_score"], item["pyramid_score"]
    assert_equal single["data_period"], item["data_period"]
    assert_equal single["last_calc_at"], item["last_calc_at"]
    assert_equal single["board"], item["board"]
    assert_equal single["sw_l1"], item["sw_l1"]
    assert_equal single["sw_l2"], item["sw_l2"]
  end

  test "ranking 分页无交集且并集覆盖 total" do
    calc = Time.current
    3.times do |i|
      create_cn_stock_with_annual(symbol: format("SH60000%d", i + 1), name: "分页股#{i}",
                                  score: 700 - i * 10, calc_at: calc)
    end

    get "/api/v1/archive/ranking?limit=2&offset=0", headers: @auth
    page1 = response.parsed_body["data"]["items"].map { |i| i["code"] }
    get "/api/v1/archive/ranking?limit=2&offset=2", headers: @auth
    page2 = response.parsed_body["data"]["items"].map { |i| i["code"] }

    assert_empty page1 & page2
    assert_equal 3, (page1 | page2).size
    assert_equal [3], response.parsed_body["data"]["items"].map { |i| i["rank"] }
  end

  test "ranking min_score 过滤生效且北交所正常入榜" do
    calc = Time.current
    create_cn_stock_with_annual(symbol: "SH600519", name: "贵州茅台", score: 900, calc_at: calc)
    create_cn_stock_with_annual(symbol: "BJ920201", name: "北交所股", score: 650, calc_at: calc)
    create_cn_stock_with_annual(symbol: "SH600000", name: "低分股", score: 500, calc_at: calc)

    get "/api/v1/archive/ranking?min_score=600", headers: @auth
    data = response.parsed_body["data"]

    assert_equal 2, data["total"]
    assert_equal %w[600519.SH 920201.BJ], data["items"].map { |i| i["code"] }
    assert_equal "北交所", data["items"].last["board"]
  end

  test "ranking limit 超上限按 1000 截断并给出 warning" do
    get "/api/v1/archive/ranking?limit=1500", headers: @auth
    assert_response 200
    assert_equal "limit 超过上限，已按 1000 截断", response.parsed_body["data"]["warning"]
  end
end
