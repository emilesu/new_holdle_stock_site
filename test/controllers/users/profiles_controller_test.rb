require "test_helper"

class Users::ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Plan.create!(plan_code: "welcome", name: "新用户体验", price_cents: 0, quota: 15)
  end

  def create_key(user, plain = "hl_testkey12345678")
    ApiKey.create!(
      user: user,
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      key_plaintext: plain,
      plan_code: "welcome",
      quota_remaining: 15,
      quota_total: 15
    )
  end

  test "登录用户可见完整 Key 明文" do
    user = users(:one)
    create_key(user)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "span[data-copy-target='source']", text: /hl_testkey12345678/
  end

  test "普通用户可见 Key 与复制按钮，但不可见安装提示词（v1.32.2 起仅 admin 可见）" do
    user = users(:one)
    create_key(user)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "button", text: "复制 Key"
    assert_select "button", text: "复制提示词", count: 0
  end

  test "管理员可见安装提示词，提示词包含 Key 与新地址" do
    user = users(:two) # admin fixture
    create_key(user)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "button", text: "复制提示词"
    assert_select "textarea", /hl_testkey12345678/
    assert_select "textarea", %r{https://ai\.holdle\.com/mcp}
    # v1.2 使用规则段（MCP 强制路由 + round_id 计费说明）
    assert_select "textarea", /使用规则（必须遵守）/
    assert_select "textarea", /holdle_get_rules/
    assert_select "textarea", /round_id/
  end

  test "无 Key 用户显示购买引导" do
    user = users(:one)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_match(/暂无 API Key/, response.body)
  end

  test "自助重新生成 Key：同 id 就地换新值，流水不断链" do
    user = users(:one)
    key = create_key(user)
    old_hash = key.key_hash
    old_id = key.id

    sign_in user
    post users_regenerate_api_key_path

    assert_redirected_to users_profile_path
    key.reload
    assert_equal old_id, key.id, "key id 不应变化"
    assert_not_equal old_hash, key.key_hash, "hash 应变化（旧 key 失效）"
    assert key.key_plaintext.present?, "应写入新明文"
    assert_match(/已重新生成/, flash[:notice])
  end

  test "无 active key 时自助重新生成给出提示" do
    user = users(:one)
    sign_in user

    post users_regenerate_api_key_path

    assert_redirected_to users_profile_path
    assert_match(/没有可重新生成的 Key/, flash[:alert])
  end

  test "未登录访问 profile 重定向到登录页" do
    get users_profile_path

    assert_redirected_to new_user_session_path
  end
end
