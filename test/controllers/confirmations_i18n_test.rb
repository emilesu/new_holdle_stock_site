require "test_helper"

# 确认/注册错误信息中文翻译回归（防 Translation missing 泄漏到界面）
class ConfirmationsI18nTest < ActionDispatch::IntegrationTest
  test "对已确认邮箱重新发送确认邮件提示中文已确认" do
    u = User.create!(email: "dup_conf@test.com", password: "password123", nickname: "重复确认", confirmed_at: Time.current)

    post user_confirmation_path, params: { user: { email: u.email } }
    assert_response :unprocessable_entity
    assert_match(/已经确认过/, response.body)
    assert_no_match(/Translation missing/, response.body)
  end

  test "无效确认令牌也显示中文而非裸英文" do
    get user_confirmation_path(confirmation_token: "bogus_token")
    assert_response :success
    assert_match(/确认链接/, response.body)
    assert_no_match(/Translation missing/, response.body)
  end

  test "注册邮箱重复时中文提示" do
    post user_registration_path, params: {
      user: { email: users(:one).email, password: "password123", password_confirmation: "password123", nickname: "重复邮箱" }
    }
    assert_response :unprocessable_entity
    assert_match(/已被其他账号使用/, response.body)
    assert_no_match(/Translation missing/, response.body)
  end

  test "忘记密码输入未注册邮箱时中文提示" do
    # 验证码化改造后：明示未注册并引导微信/Google 用户（替代 Devise not_found 翻译）
    post user_password_path, params: { email: "nobody_nowhere@test.com" }
    assert_response :unprocessable_content
    assert_match(/该邮箱未注册/, response.body)
    assert_match(/个人中心绑定/, response.body)
    assert_no_match(/Translation missing/, response.body)
  end

  test "重新发送确认邮件输入未注册邮箱时中文提示" do
    post user_confirmation_path, params: { user: { email: "nobody_nowhere2@test.com" } }
    assert_response :unprocessable_entity
    assert_match(/尚未注册/, response.body)
    assert_no_match(/Translation missing/, response.body)
  end
end
