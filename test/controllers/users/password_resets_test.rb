require "test_helper"

# 忘记密码：邮箱验证码方式（替代 Devise 邮件重置链接，防预取机器人秒消费 token）
class Users::PasswordResetsTest < ActionDispatch::IntegrationTest
  setup { ActionMailer::Base.deliveries.clear }

  test "发码后凭码重置成功并跳登录页" do
    user = users(:one)
    post user_password_path, params: { email: user.email }
    assert_response :unprocessable_content # Turbo 表单 200 会被静默丢弃，422 就地渲染
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b(\d{6})\b/, 1]

    perform_enqueued_jobs do # 密码变更通知走队列
      patch user_password_path, params: { email: user.email, code: code, password: "resetpass1", password_confirmation: "resetpass1" }
    end
    assert_redirected_to new_user_session_path
    assert user.reload.valid_password?("resetpass1")
  end

  test "未注册邮箱明示未注册并引导第三方登录用户" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post user_password_path, params: { email: "nobody@nowhere.com" }
    end
    assert_response :unprocessable_content
    assert_match(/未注册/, flash[:alert].to_s)
  end

  test "错误验证码不重置" do
    user = users(:one)
    post user_password_path, params: { email: user.email }
    patch user_password_path, params: { email: user.email, code: "000000", password: "resetpass1", password_confirmation: "resetpass1" }
    assert_response :unprocessable_content
    assert user.reload.valid_password?("password123")
  end

  test "旧邮件链接入口重定向回验证码流程" do
    get edit_user_password_path(reset_password_token: "legacy-token")
    assert_redirected_to new_user_password_path
  end

  test "未确认账号凭码重置视同完成邮箱确认" do
    unconfirmed = User.create!(email: "unconf@test.com", password: "password123", nickname: "未确认用户")
    post user_password_path, params: { email: unconfirmed.email }
    code = ActionMailer::Base.deliveries.last.text_part.body.decoded[/\b(\d{6})\b/, 1]
    perform_enqueued_jobs do
      patch user_password_path, params: { email: unconfirmed.email, code: code, password: "resetpass1", password_confirmation: "resetpass1" }
    end
    assert unconfirmed.reload.confirmed?
  end
end
