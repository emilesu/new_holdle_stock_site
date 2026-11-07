require "test_helper"

# PR-7 自助归并：新壳账号凭原账号邮箱+密码并入老账号
class Users::ClaimsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # 老账号：真实邮箱 + 密码 + 会员 + 收藏
    @old = User.create!(email: "veteran@test.com", password: "oldpassword", nickname: "2019老用户",
                        role: "member", member_expire_at: 3.years.from_now, confirmed_at: Time.current,
                        onboarded_at: 1.year.ago)
    @old.favorite!(stocks(:one))

    # 新壳账号：微信刚注册
    @shell = User.create!(email: "wx_shell@wechat-auto.local", password: "password123", nickname: "微信新壳",
                          confirmed_at: Time.current, weixin_unionid: "shell_union", weixin_web_openid: "shell_openid")
    sign_in @shell
  end

  test "验证通过后并入老账号且壳账号归档" do
    assert_difference "MergeLog.count", 1 do
      post users_claim_path, params: { email: @old.email, password: "oldpassword" }
    end
    assert_redirected_to users_profile_path

    @shell.reload
    assert_predicate @shell, :archived?
    @old.reload
    assert_equal "shell_union", @old.weixin_unionid, "微信凭据应补入老账号"
    assert_equal 1, @old.user_favorites.count

    # 会话已切换到老账号
    get users_profile_path
    assert_response :success
  end

  test "密码错误不合并且文案统一" do
    assert_no_difference "MergeLog.count" do
      post users_claim_path, params: { email: @old.email, password: "wrong" }
    end
    assert_redirected_to onboarding_path
    assert_not @shell.reload.archived?
  end

  test "邮箱不存在同样拒绝（防账号探测文案一致）" do
    post users_claim_path, params: { email: "ghost@test.com", password: "whatever" }
    assert_redirected_to onboarding_path
  end

  test "超过 3 次尝试后拒绝" do
    4.times { post users_claim_path, params: { email: @old.email, password: "wrong" } }
    post users_claim_path, params: { email: @old.email, password: "oldpassword" }
    assert_not @shell.reload.archived?
  end

  test "老账号（注册超7天）无归并资格" do
    sign_in @old
    post users_claim_path, params: { email: "veteran@test.com", password: "oldpassword" }
    assert_redirected_to root_path
  end

  test "onboarding 页对壳账号显示归并引导" do
    get onboarding_path
    assert_response :success
    assert_select "form[action=?]", users_claim_path
  end

  test "普通新邮箱注册用户不显示归并引导" do
    normal = User.create!(email: "plain_new@test.com", password: "password123", nickname: "普通新用户", confirmed_at: Time.current)
    sign_in normal
    get onboarding_path
    assert_response :success
    assert_select "form[action=?]", users_claim_path, count: 0
  end
end
