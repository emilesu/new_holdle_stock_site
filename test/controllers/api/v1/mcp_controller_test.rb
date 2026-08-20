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
end
