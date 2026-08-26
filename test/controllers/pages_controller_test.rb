require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "join 页公开可访问，渲染新版定价与教程链接" do
    get join_path
    assert_response :success
    assert_match "免费领 15 次体验", response.body
    assert_match "永久会员", response.body
    assert_select "a[href='/ai-assistant']", text: "看使用教程"
  end

  test "plans 页在无套餐数据时显示空态提示" do
    get plans_path
    assert_response :success
    assert_match "暂无可用套餐", response.body
  end

  test "plans 页有套餐时渲染卡片，登录用户显示当前 key 状态" do
    Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46800, quota: nil, active: true, is_member_upgrade: true)
    user = users(:one)
    ApiKey.create!(
      user: user,
      key_hash: Digest::SHA256.hexdigest("hl_testkey12345678"),
      key_prefix: "hl_testkey12",
      key_plaintext: "hl_testkey12345678",
      plan_code: "welcome",
      quota_remaining: 15,
      quota_total: 15
    )
    sign_in user

    get plans_path
    assert_response :success
    assert_match "永久会员", response.body
    assert_match "立即购买", response.body
    assert_match "当前账号", response.body
  end
end
