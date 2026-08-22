require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @onboarded_user = users(:one)
    @admin = users(:two)
  end

  def create_new_user(email = "new_user@test.com")
    User.create!(email: email, password: "password123", nickname: "新用户", onboarded_at: nil)
  end

  # ===== show 页 =====

  test "未登录访问引导页重定向到登录页" do
    get onboarding_path
    assert_redirected_to new_user_session_path
  end

  test "已完成引导的用户访问引导页重定向到首页" do
    sign_in @onboarded_user
    get onboarding_path
    assert_redirected_to root_path
  end

  test "新用户能看到引导页（两个选择 + 跳过）" do
    user = create_new_user
    sign_in user
    get onboarding_path
    assert_response :success
    assert_select "h1", /欢迎加入 HOLD LE/
    assert_select "button", text: "去配置 AI 投研助手"
    assert_select "button", text: "去交易课学习"
    assert_select "button", text: /先逛逛首页/
  end

  test "新用户引导页展示剩余次数" do
    user = create_new_user
    ApiKey.create!(
      user: user,
      key_hash: Digest::SHA256.hexdigest("hl_newkey12345678"),
      key_prefix: "hl_newkey12",
      key_plaintext: "hl_newkey12345678",
      plan_code: "welcome",
      quota_remaining: 15,
      quota_total: 15
    )
    sign_in user
    get onboarding_path
    assert_response :success
    assert_match(/15 次免费体验已到账，剩余 15 次/, response.body)
  end

  test "管理员可通过 preview=1 预览引导页（已完成引导也放行）" do
    sign_in @admin
    get onboarding_path(preview: 1)
    assert_response :success
    assert_match(/预览模式/, response.body)
  end

  # ===== complete 动作 =====

  test "完成引导选 profile：写入 onboarded_at 并跳个人中心" do
    user = create_new_user
    sign_in user
    post onboarding_complete_path, params: { target: "profile" }
    assert_redirected_to users_profile_path
    assert user.reload.onboarded_at.present?
  end

  test "完成引导选 courses：跳交易课" do
    user = create_new_user
    sign_in user
    post onboarding_complete_path, params: { target: "courses" }
    assert_redirected_to courses_path
    assert user.reload.onboarded_at.present?
  end

  test "跳过引导：回首页并写入 onboarded_at（不再打扰）" do
    user = create_new_user
    sign_in user
    post onboarding_complete_path, params: { target: "skip" }
    assert_redirected_to root_path
    assert user.reload.onboarded_at.present?
  end

  test "非法 target 一律回首页兜底（防开放重定向）" do
    user = create_new_user
    sign_in user
    post onboarding_complete_path, params: { target: "javascript:alert(1)" }
    assert_redirected_to root_path
  end

  test "管理员预览模式下完成引导不写入 onboarded_at" do
    original = @admin.onboarded_at
    sign_in @admin
    post onboarding_complete_path, params: { target: "profile", preview: "1" }
    assert_redirected_to users_profile_path
    assert_equal original, @admin.reload.onboarded_at
  end

  # ===== 兜底守卫 =====

  test "未完成引导的用户访问首页被强制跳引导页" do
    user = create_new_user
    sign_in user
    get root_path
    assert_redirected_to onboarding_path
  end

  test "管理员不受兜底守卫限制" do
    sign_in @admin
    get root_path
    assert_response :success
  end

  test "已完成引导的用户访问首页正常" do
    sign_in @onboarded_user
    get root_path
    assert_response :success
  end

  # ===== 邮箱注册跳转（自定义 RegistrationsController） =====

  test "邮箱注册成功后跳转引导页" do
    post user_registration_path, params: {
      user: { email: "signup_test@test.com", password: "password123", password_confirmation: "password123", nickname: "注册用户" }
    }
    assert_redirected_to onboarding_path
  end
end
