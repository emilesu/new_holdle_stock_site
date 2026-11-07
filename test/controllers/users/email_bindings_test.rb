require "test_helper"

# PR-6 绑定真实邮箱 + 占位账号首设密码
class Users::EmailBindingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @wx = User.create!(email: "wx_demo@wechat-auto.local", password: "password123",
                       nickname: "微信老用户", confirmed_at: Time.current,
                       weixin_unionid: "demo_union")
    sign_in @wx
    ActionMailer::Base.deliveries.clear
  end

  test "发码后凭码绑定邮箱并首设密码" do
    assert_difference "EmailVerification.count", 1 do
      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        post users_email_binding_code_path, params: { email: "demo@gmail.com" }
      end
    end

    code = ActionMailer::Base.deliveries.last.decoded.to_s[/\b(\d{6})\b/, 1]
    assert code, "邮件正文应包含 6 位验证码"

    patch users_email_binding_path, params: { code: code, password: "newpass123", password_confirmation: "newpass123" }
    @wx.reload
    assert_equal "demo@gmail.com", @wx.email
    assert @wx.confirmed?
    assert @wx.valid_password?("newpass123")
    assert_equal 0, EmailVerification.count
  end

  test "邮箱已被占用时不发码" do
    assert_no_difference "EmailVerification.count" do
      post users_email_binding_code_path, params: { email: users(:one).email }
    end
  end

  test "错误验证码不改变邮箱" do
    post users_email_binding_code_path, params: { email: "demo@gmail.com" }
    patch users_email_binding_path, params: { code: "000000", password: "newpass123", password_confirmation: "newpass123" }
    assert_equal "wx_demo@wechat-auto.local", @wx.reload.email
  end

  test "两次密码不一致时提前拦截且不消耗验证码" do
    post users_email_binding_code_path, params: { email: "demo@gmail.com" }
    code = ActionMailer::Base.deliveries.last.decoded.to_s[/\b(\d{6})\b/, 1]
    patch users_email_binding_path, params: { code: code, password: "newpass123", password_confirmation: "different" }
    @wx.reload
    assert_equal "wx_demo@wechat-auto.local", @wx.email
    assert_match(/密码不一致/, flash[:alert].to_s)
    assert_equal 1, EmailVerification.count, "验证码不应被消耗，可直接改正重交"

    # 改正后凭原验证码直接成功
    patch users_email_binding_path, params: { code: code, password: "newpass123", password_confirmation: "newpass123" }
    assert_equal "demo@gmail.com", @wx.reload.email
  end

  test "占位邮箱账号改密免当前密码" do
    patch users_update_profile_password_path, params: { user: { password: "abc12345", password_confirmation: "abc12345" } }
    assert @wx.reload.valid_password?("abc12345")
  end

  test "真实邮箱账号改密仍需当前密码" do
    real = users(:one)
    sign_in real
    patch users_update_profile_password_path, params: { user: { current_password: "wrong", password: "abc12345", password_confirmation: "abc12345" } }
    assert_not real.reload.valid_password?("abc12345")
  end

  test "邮箱注册触发确认邮件且宽限期内可登录" do
    delete destroy_user_session_path # 注册页要求未登录（Devise require_no_authentication）
    ActionMailer::Base.deliveries.clear
    assert_difference "User.count", 1 do
      perform_enqueued_jobs do # PR-8：Devise 确认邮件经队列投递
        post user_registration_path, params: {
          user: { email: "fresh@test.com", password: "password123", password_confirmation: "password123", nickname: "新注册" }
        }
      end
    end
    created = User.find_by(email: "fresh@test.com")
    assert_nil created.confirmed_at
    assert_not_nil created.confirmation_sent_at
    assert_equal 1, ActionMailer::Base.deliveries.size

    # 24h 宽限期内可正常登录（登录成功跳首页；未确认被拦则回登录页）
    delete destroy_user_session_path
    post user_session_path, params: { user: { email: "fresh@test.com", password: "password123" } }
    assert_redirected_to root_path
  end
end
