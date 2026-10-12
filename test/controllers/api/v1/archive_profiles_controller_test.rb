require "test_helper"

# 发布通道 API：鉴权 / 校验闸门 / 幂等 / 撤回 / 查询
class Api::V1::ArchiveProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["HOLDLE_PUBLISH_TOKEN"] = "publish-test-token"
    @auth = { "Authorization" => "Bearer publish-test-token" }
    @stock = create_stock_with_annual
  end

  teardown do
    ENV.delete("HOLDLE_PUBLISH_TOKEN")
  end

  def create_stock_with_annual(symbol: "SH603259", score: 800)
    stock = Stock.create!(symbol: symbol, name: "药明康德", market: "CN", sector: "医药生物",
                          industry: "医疗服务", exchange: "SHSE", status: "active",
                          pyramid_total_score: score, last_pyramid_calc_at: Time.current)
    fr = FinancialReport.create!(stock: stock, report_date: Date.new(2025, 12, 31),
                                 report_type: "CN_ANNUAL", market: "CN",
                                 period_type: "annual", currency: "CNY")
    FinancialIndicator.create!(financial_report: fr, stock: stock,
                               report_date: Date.new(2025, 12, 31), market: "CN",
                               period_type: "annual")
    stock
  end

  def post_profile(headers: @auth, **overrides)
    params = { code: "SH603259", period: "2025年报", title: "药明康德 2025 档案",
               markdown: "正文内容", meta: { "gate_passed" => true, "ai_generated" => true } }
                 .merge(overrides)
    post "/api/v1/archive/profiles", params: params, as: :json, headers: headers
  end

  # ---- 鉴权（fail-closed） ----

  test "无 token / 错误 token 返回 401" do
    post_profile(headers: {})
    assert_response 401
    post_profile(headers: { "Authorization" => "Bearer wrong" })
    assert_response 401
  end

  test "ENV 未配置 token 时拒绝一切请求（fail-closed）" do
    ENV["HOLDLE_PUBLISH_TOKEN"] = ""
    post_profile
    assert_response 401
  end

  # ---- 校验 ----

  test "未知 code 返回 404" do
    post_profile(code: "SH999999")
    assert_response 404
  end

  test "period 非法标签（半年报）返回 422" do
    post_profile(period: "2025半年报")
    assert_response 422
  end

  test "孤儿期次（库内无该期财务数据）返回 422" do
    post_profile(period: "2025中报")
    assert_response 422
    assert_includes response.parsed_body["error"], "已披露期次"
  end

  test "title/markdown 缺失与 meta 布尔校验返回 422" do
    post_profile(title: "  ")
    assert_response 422
    post_profile(markdown: "")
    assert_response 422
    post_profile(meta: { "gate_passed" => "true", "ai_generated" => true })
    assert_response 422
    post_profile(meta: { "gate_passed" => true, "ai_generated" => 1 })
    assert_response 422
    post_profile(meta: "不是对象")
    assert_response 422
    assert_includes response.parsed_body["error"], "meta 必须为对象"
  end

  # ---- 发布与幂等 ----

  test "首发 201 进待审队列，覆盖 200 版本递增，状态永不为 published" do
    post_profile
    assert_response 201
    data = response.parsed_body["data"]
    assert_equal "pending_review", data["status"]
    assert_equal 1, data["version_no"]
    profile_id = data["profile_id"]

    post_profile(markdown: "第二稿")
    assert_response 200
    data2 = response.parsed_body["data"]
    assert_equal profile_id, data2["profile_id"] # 幂等：同一行
    assert_equal 2, data2["version_no"]
    assert_equal "pending_review", data2["status"]

    # gate_passed=false 只到 draft
    post_profile(meta: { "gate_passed" => false, "ai_generated" => true })
    assert_response 200
    assert_equal "draft", response.parsed_body["data"]["status"]
  end

  test "后缀式与小写 code 归一化命中同一档案行" do
    post_profile(code: "603259.SH")
    assert_response 201
    first_id = response.parsed_body["data"]["profile_id"]
    assert_equal "603259.SH", response.parsed_body["data"]["code"]

    post_profile(code: "sh603259")
    assert_response 200
    assert_equal first_id, response.parsed_body["data"]["profile_id"]
  end

  test "传入分数与库内不一致时回填库内值并返回 warning" do
    post_profile(meta: { "gate_passed" => true, "ai_generated" => true, "pyramid_score" => 700 })
    assert_response 201
    assert_match(/与库内 800 不一致/, response.parsed_body["data"]["warning"])
    assert_equal 800, QualityProfile.find_by(stock_id: @stock.id).meta["pyramid_score"]
  end

  # ---- 撤回 ----

  test "withdraw 置撤回且幂等" do
    post_profile
    id = response.parsed_body["data"]["profile_id"]

    post "/api/v1/archive/profiles/#{id}/withdraw", headers: @auth
    assert_response 200
    assert_equal "withdrawn", response.parsed_body["data"]["status"]

    post "/api/v1/archive/profiles/#{id}/withdraw", headers: @auth
    assert_response 200
    assert_equal "withdrawn", QualityProfile.find(id).status

    post "/api/v1/archive/profiles/999999/withdraw", headers: @auth
    assert_response 404
  end

  # ---- 查询 ----

  test "index 支持 code/status 过滤并返回版本指针" do
    post_profile
    get "/api/v1/archive/profiles?code=603259.SH&status=pending_review", headers: @auth
    assert_response 200
    rows = response.parsed_body["data"]
    assert_equal 1, rows.size
    assert_equal "2025年报", rows.first["period"]
    assert_equal 1, rows.first["current_version_no"]
    assert_nil rows.first["published_version_no"]

    get "/api/v1/archive/profiles?code=SH603259&status=published", headers: @auth
    assert_equal [], response.parsed_body["data"]
  end
end
