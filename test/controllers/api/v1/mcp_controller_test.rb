require "test_helper"

class Api::V1::McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["MCP_SERVICE_TOKEN"] = "test-token"
    @auth = { "Authorization" => "Bearer test-token" }
  end

  # 构造一个可用的 api_key，返回明文（仅测试内使用）
  # quota 作用于 key 的 quota_remaining（plan 的 quota 保持正数以通过校验）
  def build_api_key(quota: 500, status: "active", plan_code: "standard")
    Plan.create!(plan_code: plan_code, name: "标准包", price_cents: 10_000, quota: 500)
    plain = "hl_" + SecureRandom.hex(8)
    ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      user: users(:one),
      plan_code: plan_code,
      status: status,
      quota_remaining: quota,
      quota_total: quota
    )
    plain
  end

  test "无 token 返回 401" do
    post api_v1_mcp_precheck_path, params: { api_key: "hl_x", request_id: SecureRandom.uuid }
    assert_response 401
    assert_equal false, response.parsed_body["ok"]
  end

  test "错误 token 返回 401" do
    post api_v1_mcp_precheck_path, params: { api_key: "hl_x", request_id: SecureRandom.uuid },
                                   headers: { "Authorization" => "Bearer wrong-token" }
    assert_response 401
  end

  test "precheck 合法 key 返回 200 且带 remaining" do
    plain = build_api_key(quota: 500)

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: SecureRandom.uuid }, headers: @auth

    assert_response 200
    body = response.parsed_body
    assert_equal true, body["ok"]
    assert_equal "standard", body["plan"]
    assert_equal 500, body["remaining"]
  end

  test "precheck 非法 key 返回 401" do
    post api_v1_mcp_precheck_path, params: { api_key: "hl_deadbeef00000000", request_id: SecureRandom.uuid }, headers: @auth
    assert_response 401
    assert_equal "key 无效", response.parsed_body["error"]
  end

  test "precheck 次数用完返回 402" do
    plain = build_api_key(quota: 0)

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: SecureRandom.uuid }, headers: @auth

    assert_response 402
    assert_equal "次数已用完，请充值", response.parsed_body["error"]
  end

  test "precheck 停用 key 返回 403" do
    plain = build_api_key(status: "disabled")

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: SecureRandom.uuid }, headers: @auth

    assert_response 403
    assert_equal "key 已停用", response.parsed_body["error"]
  end

  test "confirm 幂等：同 request_id 只扣一次" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200

    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200
    assert_equal 1, response.parsed_body["consumed"]
    assert_equal 9, response.parsed_body["remaining"]

    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200
    assert_equal true, response.parsed_body["already_processed"]

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
  end

  test "confirm 未先 precheck 返回 404" do
    post api_v1_mcp_confirm_path, params: { api_key: "hl_x", request_id: SecureRandom.uuid }, headers: @auth
    assert_response 404
    assert_equal "request 不存在", response.parsed_body["error"]
  end

  test "release 不扣次且幂等" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200

    post api_v1_mcp_release_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200
    assert_equal true, response.parsed_body["released"]

    # 重复 release 仍 200
    post api_v1_mcp_release_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200

    assert_equal 10, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal "released", UsageLog.find_by(request_id: request_id).status
  end

  test "release 未先 precheck 仍返回 200（幂等）" do
    post api_v1_mcp_release_path, params: { api_key: "hl_x", request_id: SecureRandom.uuid }, headers: @auth
    assert_response 200
    assert_equal true, response.parsed_body["released"]
  end

  test "precheck 缺 request_id 返回 400" do
    plain = build_api_key(quota: 10)

    post api_v1_mcp_precheck_path, params: { api_key: plain }, headers: @auth
    assert_response 400
    assert_equal "request_id 缺失", response.parsed_body["error"]
  end

  test "precheck 无限次 key 返回 200 且 remaining 为 nil" do
    plain = build_api_key(quota: nil, plan_code: "member_permanent")

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: SecureRandom.uuid }, headers: @auth

    assert_response 200
    body = response.parsed_body
    assert_equal true, body["ok"]
    assert_equal "member_permanent", body["plan"]
    assert_nil body["remaining"]
  end

  test "confirm 已释放的 request 返回 400 且不扣次" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    post api_v1_mcp_release_path, params: { api_key: plain, request_id: request_id }, headers: @auth

    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 400
    assert_equal "request 已释放", response.parsed_body["error"]

    assert_equal 10, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
  end

  test "confirm key 与预占不一致返回 400 且不扣次" do
    plain_a = build_api_key(quota: 10)
    plain_b = build_api_key(quota: 10, plan_code: "light")
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain_a, request_id: request_id }, headers: @auth
    assert_response 200

    post api_v1_mcp_confirm_path, params: { api_key: plain_b, request_id: request_id }, headers: @auth
    assert_response 400
    assert_equal "key 与预占不一致", response.parsed_body["error"]

    assert_equal 10, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain_a)).quota_remaining
  end

  test "precheck 记录 usage_log 且 request_id 幂等" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth

    assert_equal 1, UsageLog.where(request_id: request_id).count
    assert_equal "precheck", UsageLog.find_by(request_id: request_id).status
  end

  test "precheck 保存 question 与 tool_name（提问分析数据源）" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: {
      api_key: plain, request_id: request_id,
      question: "如何看待突破买入时机", tool_name: "holdle_ask"
    }, headers: @auth

    assert_response 200
    log = UsageLog.find_by(request_id: request_id)
    assert_equal "如何看待突破买入时机", log.question
    assert_equal "holdle_ask", log.tool_name
  end

  test "precheck 不传 question/tool_name 时兼容存 nil" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth

    assert_response 200
    log = UsageLog.find_by(request_id: request_id)
    assert_nil log.question
    assert_nil log.tool_name
  end

  test "confirm 兜底补写 question：precheck 未传时用 confirm 携带的 question" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_nil UsageLog.find_by(request_id: request_id).question

    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id, question: "如何看待突破买入时机" }, headers: @auth
    assert_response 200
    log = UsageLog.find_by(request_id: request_id)
    assert_equal "confirmed", log.status
    assert_equal "如何看待突破买入时机", log.question
  end

  test "confirm 不覆盖 precheck 已保存的 question" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id, question: "precheck问题" }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id, question: "confirm问题" }, headers: @auth
    assert_response 200

    assert_equal "precheck问题", UsageLog.find_by(request_id: request_id).question
  end

  # === 扣次粒度修复（90s 滑动窗口）测试 ===

  # 单次 precheck+confirm（供 confirm_sequence 复用）
  def post_confirm(plain)
    request_id = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    assert_response 200
  end

  # 按间隔序列（秒）连续 precheck+confirm：第一个请求在基准时间点，之后每个间隔后发一次请求
  def confirm_sequence(plain, intervals)
    travel_to Time.current
    post_confirm(plain)
    intervals.each do |secs|
      travel secs.seconds
      post_confirm(plain)
    end
  ensure
    travel_back
  end

  test "90 秒窗口内连续 confirm 合并为一次扣费" do
    plain = build_api_key(quota: 10)
    travel_to Time.current

    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1 }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1 }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]
    assert_equal 9, response.parsed_body["remaining"]
    round1 = response.parsed_body["round_id"]
    assert_not_nil round1

    travel 30.seconds
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2 }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2 }, headers: @auth
    assert_equal true, response.parsed_body["merged"]
    assert_equal 0, response.parsed_body["consumed"]
    assert_equal 9, response.parsed_body["remaining"]
    assert_equal round1, response.parsed_body["round_id"] # 合并沿用第一回合 round_id

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 1, UsageLog.where(status: "confirmed").count
    assert_equal 1, UsageLog.where(status: "merged").count
  ensure
    travel_back
  end

  test "间隔超过 90 秒断开为新回合各扣一次" do
    plain = build_api_key(quota: 10)
    travel_to Time.current

    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1 }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1 }, headers: @auth
    assert_equal 9, response.parsed_body["remaining"]
    round1 = response.parsed_body["round_id"]

    travel 100.seconds
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2 }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2 }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]
    assert_equal 8, response.parsed_body["remaining"]
    assert_not_equal round1, response.parsed_body["round_id"] # 新回合

    assert_equal 8, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 2, UsageLog.where(status: "confirmed").count
  ensure
    travel_back
  end

  test "merged 记录重复 confirm 返回 already_processed 幂等" do
    plain = build_api_key(quota: 10)

    travel_to Time.current do
      r1 = SecureRandom.uuid
      post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1 }, headers: @auth
      post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1 }, headers: @auth

      r2 = SecureRandom.uuid
      post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2 }, headers: @auth
      post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2 }, headers: @auth
      assert_equal true, response.parsed_body["merged"]

      post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2 }, headers: @auth
      assert_equal true, response.parsed_body["already_processed"]
    end

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 1, UsageLog.where(status: "confirmed").count
    assert_equal 1, UsageLog.where(status: "merged").count
  end

  test "precheck 透传 round_id 落库，confirm 沿用" do
    plain = build_api_key(quota: 10)
    round_id = SecureRandom.uuid
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id, round_id: round_id }, headers: @auth
    assert_response 200
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth

    assert_equal round_id, response.parsed_body["round_id"]
    assert_equal round_id, UsageLog.find_by(request_id: request_id).round_id
  end

  test "confirm 不传 round_id 时 Rails 生成兜底" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth

    assert_not_nil response.parsed_body["round_id"]
    assert_not_nil UsageLog.find_by(request_id: request_id).round_id
  end

  test "release 不改动 confirmed 终态记录" do
    plain = build_api_key(quota: 10)
    request_id = SecureRandom.uuid

    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: request_id }, headers: @auth
    post api_v1_mcp_release_path, params: { api_key: plain, request_id: request_id }, headers: @auth

    assert_equal "confirmed", UsageLog.find_by(request_id: request_id).status
  end

  test "需求验证样例：间隔全部 ≤90s（20,80,40,40,85,70）只扣 1 次" do
    plain = build_api_key(quota: 10)

    confirm_sequence(plain, [20, 80, 40, 40, 85, 70])

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 1, UsageLog.where(status: "confirmed").count
    assert_equal 6, UsageLog.where(status: "merged").count
    assert_equal 7, UsageLog.count
  end

  test "需求验证样例：两处断开（20,80,100,40,20,70,120,20）扣 3 次" do
    plain = build_api_key(quota: 10)

    confirm_sequence(plain, [20, 80, 100, 40, 20, 70, 120, 20])

    assert_equal 7, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 3, UsageLog.where(status: "confirmed").count
    assert_equal 6, UsageLog.where(status: "merged").count
    assert_equal 9, UsageLog.count
  end

  # === round_id 优先判定（v1.36.2，MCP 端实测补丁）测试 ===

  test "round_id 优先：同 round_id 间隔超过 90 秒仍合并（复盘长链不误拆）" do
    plain = build_api_key(quota: 10)
    travel_to Time.current
    round = SecureRandom.uuid

    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]
    assert_equal round, response.parsed_body["round_id"]

    # 100 秒后再检索，同一 round_id → 合并不扣费（验收用例 2 反例）
    travel 100.seconds
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2, round_id: round }, headers: @auth
    assert_equal true, response.parsed_body["merged"]
    assert_equal 0, response.parsed_body["consumed"]
    assert_equal round, response.parsed_body["round_id"]

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 1, UsageLog.where(status: "confirmed").count
    assert_equal 1, UsageLog.where(status: "merged").count
  ensure
    travel_back
  end

  test "round_id 优先：换 round_id 90 秒内连问拆为新回合各扣一次（防白嫖）" do
    plain = build_api_key(quota: 10)
    travel_to Time.current

    round_a = SecureRandom.uuid
    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1, round_id: round_a }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1, round_id: round_a }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]

    # 30 秒后问问题 B（新 round_id）→ 必须新回合扣费（验收用例 3 反例）
    travel 30.seconds
    round_b = SecureRandom.uuid
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2, round_id: round_b }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2, round_id: round_b }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]
    assert_nil response.parsed_body["merged"] # 新回合响应无 merged 标记
    assert_equal round_b, response.parsed_body["round_id"]

    assert_equal 8, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 2, UsageLog.where(status: "confirmed").count
  ensure
    travel_back
  end

  test "round_id 优先：同 round_id 90 秒内合并" do
    plain = build_api_key(quota: 10)
    travel_to Time.current
    round = SecureRandom.uuid

    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]

    travel 30.seconds
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2, round_id: round }, headers: @auth
    assert_equal true, response.parsed_body["merged"]
    assert_equal 0, response.parsed_body["consumed"]
    assert_equal round, response.parsed_body["round_id"]

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
  ensure
    travel_back
  end

  test "round_id 优先：换 round_id 且间隔超 90 秒拆新回合" do
    plain = build_api_key(quota: 10)
    travel_to Time.current

    round_a = SecureRandom.uuid
    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1, round_id: round_a }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1, round_id: round_a }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]

    travel 120.seconds
    round_b = SecureRandom.uuid
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2, round_id: round_b }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2, round_id: round_b }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]
    assert_nil response.parsed_body["merged"] # 新回合响应无 merged 标记
    assert_equal round_b, response.parsed_body["round_id"]

    assert_equal 8, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 2, UsageLog.where(status: "confirmed").count
  ensure
    travel_back
  end

  test "round_id 优先：同 round_id 连续 3 次调用只扣 1 次（last 为 merged 仍合并）" do
    plain = build_api_key(quota: 10)
    travel_to Time.current
    round = SecureRandom.uuid

    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]

    travel 30.seconds
    r2 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r2, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r2, round_id: round }, headers: @auth
    assert_equal true, response.parsed_body["merged"]

    # 第 3 次：last 为同 round 的 merged 记录，仍合并（契约验收用例 1：1 confirmed + 2 merged）
    travel 30.seconds
    r3 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r3, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r3, round_id: round }, headers: @auth
    assert_equal true, response.parsed_body["merged"]
    assert_equal 0, response.parsed_body["consumed"]
    assert_equal round, response.parsed_body["round_id"]

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 1, UsageLog.where(status: "confirmed").count
    assert_equal 2, UsageLog.where(status: "merged").count
  ensure
    travel_back
  end

  test "round_id 优先：上一条为老数据 round_id=nil 时传新 round_id 开新回合" do
    plain = build_api_key(quota: 10)
    travel_to Time.current

    # 模拟迁移前老数据：confirmed 记录无 round_id
    api_key = ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain))
    UsageLog.create!(api_key_id: api_key.id, user_id: api_key.user_id, request_id: SecureRandom.uuid,
                     tool_name: "holdle_ask", question: "老问题", status: "confirmed",
                     consumed: 1, confirmed_at: 5.minutes.ago)

    round = SecureRandom.uuid
    r1 = SecureRandom.uuid
    post api_v1_mcp_precheck_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    post api_v1_mcp_confirm_path, params: { api_key: plain, request_id: r1, round_id: round }, headers: @auth
    assert_equal 1, response.parsed_body["consumed"]
    assert_equal round, response.parsed_body["round_id"]

    assert_equal 9, ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain)).quota_remaining
    assert_equal 2, UsageLog.where(status: "confirmed").count
  ensure
    travel_back
  end
end
