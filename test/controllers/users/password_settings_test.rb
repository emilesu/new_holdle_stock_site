require "test_helper"

# 登录态「绑定邮箱验证码」设置/修改登录密码（免当前密码）
class Users::PasswordSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    ActionMailer::Base.deliveries.clear
  end

  test "发码后凭码改密成功" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post users_password_setting_code_path
    end
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b(\d{6})\b/, 1]

    perform_enqueued_jobs do # 密码变更通知走队列
      patch users_password_setting_path, params: { code: code, password: "newpass123", password_confirmation: "newpass123" }
    end
    assert @user.reload.valid_password?("newpass123")
    assert_equal 0, EmailVerification.where(purpose: "set_password").count
  end

  test "错误验证码不改密" do
    post users_password_setting_code_path
    patch users_password_setting_path, params: { code: "000000", password: "newpass123", password_confirmation: "newpass123" }
    assert @user.reload.valid_password?("password123")
    assert_match(/验证码不正确/, flash[:password_error].to_s)
  end

  test "两次密码不一致提前拦截且不消耗验证码" do
    post users_password_setting_code_path
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b(\d{6})\b/, 1]
    patch users_password_setting_path, params: { code: code, password: "newpass123", password_confirmation: "different" }
    assert_match(/密码不一致/, flash[:password_error].to_s)
    assert_equal 1, EmailVerification.where(purpose: "set_password").count

    perform_enqueued_jobs do
      patch users_password_setting_path, params: { code: code, password: "newpass123", password_confirmation: "newpass123" }
    end
    assert @user.reload.valid_password?("newpass123")
  end

  test "占位邮箱账号请求发码被拦截" do
    shell = User.create!(email: "wx_p@wechat-auto.local", password: "password123", nickname: "壳用户", confirmed_at: Time.current)
    sign_in shell
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post users_password_setting_code_path
    end
    assert_match(/绑定/, flash[:password_error].to_s)
  end

  test "未登录访问跳登录页" do
    delete destroy_user_session_path
    post users_password_setting_code_path
    assert_redirected_to new_user_session_path
  end
end
