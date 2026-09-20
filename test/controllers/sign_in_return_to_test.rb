require "test_helper"

# 登录/注册后回到来源页（return_to）的跳转链路
class SignInReturnToTest < ActionDispatch::IntegrationTest
  setup do
    @credentials = { user: { email: users(:one).email, password: "password123" } }
  end

  test "带 return_to 从登录页登录后跳回原页面" do
    get new_user_session_path(return_to: about_path)
    assert_response :success

    post user_session_path, params: @credentials
    assert_redirected_to about_path
  end

  test "未带 return_to 登录后仍回首页" do
    get new_user_session_path

    post user_session_path, params: @credentials
    assert_redirected_to root_path
  end

  test "外域 return_to 被拒绝，登录后回首页" do
    get new_user_session_path(return_to: "http://evil.com/phish")

    post user_session_path, params: @credentials
    assert_redirected_to root_path
  end

  test "协议相对地址 return_to 被拒绝，登录后回首页" do
    get new_user_session_path(return_to: "//evil.com/phish")

    post user_session_path, params: @credentials
    assert_redirected_to root_path
  end

  test "指向登录页自身的 return_to 被拒绝，避免跳转循环" do
    get new_user_session_path(return_to: new_user_session_path)

    post user_session_path, params: @credentials
    assert_redirected_to root_path
  end

  test "同站绝对 URL 的 return_to 只保留路径" do
    get new_user_session_path(return_to: "http://www.example.com#{about_path}")

    post user_session_path, params: @credentials
    assert_redirected_to about_path
  end

  test "新用户带 return_to 注册后回原页面，引导只延后一次" do
    get new_user_registration_path(return_to: about_path)
    assert_response :success

    post user_registration_path, params: {
      user: {
        email: "return_to_signup@test.com",
        password: "password123",
        password_confirmation: "password123",
        nickname: "回源用户"
      }
    }
    assert_redirected_to about_path

    follow_redirect! # 消耗一次性放行标记
    assert_response :success

    get root_path
    assert_redirected_to onboarding_path
  end
end