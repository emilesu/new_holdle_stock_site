require "test_helper"

# PR-8 安全加固：锁定、密码长度、安全通知、归档文案
class SessionsSecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = users(:one)
  end

  test "5 次登录失败锁定，15 分钟后自动解锁" do
    5.times { post user_session_path, params: { user: { email: @user.email, password: "wrongpassword" } } }
    assert @user.reload.access_locked?

    # 锁定期内即使密码正确也拒绝（Rails 7.1 认证失败渲染登录页 422）
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_response :unprocessable_entity
    assert_match(/锁定/, flash[:alert].to_s)

    travel 16.minutes do
      post user_session_path, params: { user: { email: @user.email, password: "password123" } }
      assert_redirected_to root_path
    end
  end

  test "第 4 次失败提示还剩一次机会" do
    4.times { post user_session_path, params: { user: { email: @user.email, password: "wrongpassword" } } }
    assert_match(/还有一次/, flash[:alert].to_s)
  end

  test "7 位密码注册被拒（最短 8 位）" do
    assert_no_difference "User.count" do
      post user_registration_path, params: {
        user: { email: "short@test.com", password: "abc1234", password_confirmation: "abc1234", nickname: "短密码" }
      }
    end
  end

  test "真实邮箱改密发送通知邮件" do
    sign_in @user
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      perform_enqueued_jobs do # PR-8：Devise 通知邮件经队列投递
        patch users_update_profile_password_path, params: {
          user: { current_password: "password123", password: "newpassword1", password_confirmation: "newpassword1" }
        }
      end
    end
  end

  test "占位邮箱改密不发通知（防 SMTP 退信 500）" do
    shell = User.create!(email: "wx_n@wechat-auto.local", password: "password123", nickname: "壳用户", confirmed_at: Time.current)
    sign_in shell
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      patch users_update_profile_password_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1" } }
    end
    assert shell.reload.valid_password?("newpassword1")
  end

  test "claim 失败累计老账号 failed_attempts" do
    old = User.create!(email: "veteran2@test.com", password: "oldpassword", nickname: "老用户二", confirmed_at: Time.current)
    shell = User.create!(email: "wx_s2@wechat-auto.local", password: "password123", nickname: "壳二", confirmed_at: Time.current, weixin_unionid: "s2_union")
    sign_in shell

    3.times { post users_claim_path, params: { email: old.email, password: "wrong" } }
    assert_equal 3, old.reload.failed_attempts
  end

  test "归档账号提示专属中文文案" do
    archived = users(:two)
    archived.update_column(:archived_at, Time.current)
    assert_equal :archived, archived.inactive_message
    assert_match(/归并/, I18n.t("devise.failure.archived"))
  end
end
