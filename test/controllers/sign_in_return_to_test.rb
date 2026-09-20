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

# 第三方登录（微信 / Google）回调同样要回到来源页
class OAuthReturnToTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @user = users(:one)
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:wechat] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "微信老用户授权后回到来源页" do
    @user.update!(weixin_unionid: "return_to_union_existing")
    get new_user_session_path(return_to: about_path)
    OmniAuth.config.mock_auth[:wechat] = wechat_auth(union_id: "return_to_union_existing", openid: "return_to_openid_existing")

    get user_wechat_omniauth_callback_path
    assert_redirected_to about_path
  end

  test "微信新用户授权后回到来源页（引导延后）" do
    get new_user_session_path(return_to: about_path)
    OmniAuth.config.mock_auth[:wechat] = wechat_auth(
      union_id: "return_to_union_new",
      openid: "return_to_openid_new",
      nickname: "回归用例微信新用户"
    )

    assert_difference "User.count", 1 do
      get user_wechat_omniauth_callback_path
    end
    assert_redirected_to about_path
  end

  test "微信老用户未带来源页时仍回首页" do
    @user.update!(weixin_unionid: "return_to_union_plain")
    get new_user_session_path
    OmniAuth.config.mock_auth[:wechat] = wechat_auth(union_id: "return_to_union_plain", openid: "return_to_openid_plain")

    get user_wechat_omniauth_callback_path
    assert_redirected_to root_path
  end

  test "Google 老用户授权后回到来源页" do
    get new_user_session_path(return_to: about_path)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "return_to_google_uid",
      info: { email: @user.email, name: "回归用例Google用户", image: "https://example.com/g.png" }
    )

    get user_google_oauth2_omniauth_callback_path
    assert_redirected_to about_path
  end

  private

  def wechat_auth(union_id:, openid:, nickname: "回归用例微信用户")
    OmniAuth::AuthHash.new(
      provider: "wechat",
      uid: openid,
      info: { nickname: nickname, image: "https://example.com/wx.png" },
      extra: { raw_info: { "unionid" => union_id } }
    )
  end
end