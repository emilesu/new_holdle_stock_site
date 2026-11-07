require "test_helper"

# PR-4 账号绑定管理：绑定分支归属正确、占用拦截、解绑守卫
class Users::IdentitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @user = users(:one)
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:wechat] = nil
  end

  test "发起绑定 Google 跳转授权路径" do
    sign_in_user(@user)
    get users_link_identity_path("google_oauth2")
    assert_redirected_to user_google_oauth2_omniauth_authorize_path
  end

  test "绑定回调把凭据挂到当前用户而非邮箱匹配账号" do
    sign_in_user(@user)
    get users_link_identity_path("google_oauth2")
    mock_google("link_uid_ok", "linker_new@gmail.com")

    assert_difference "Identity.count", 1 do
      get user_google_oauth2_omniauth_callback_path
    end
    assert_redirected_to users_profile_path
    assert_equal "link_uid_ok", @user.reload.google_identity&.uid
  end

  test "绑定回调遇他人邮箱归属拦截" do
    other = users(:two)
    sign_in_user(@user)
    get users_link_identity_path("google_oauth2")
    mock_google("link_uid_taken", other.email)

    assert_no_difference "Identity.count" do
      get user_google_oauth2_omniauth_callback_path
    end
    assert_redirected_to users_profile_path
  end

  test "微信绑定回调挂凭据到当前账号" do
    sign_in_user(@user)
    get users_link_identity_path("wechat")
    OmniAuth.config.mock_auth[:wechat] = OmniAuth::AuthHash.new(
      provider: "wechat", uid: "link_wx_openid",
      info: { nickname: "绑定微信", image: "https://example.com/wx.png" },
      extra: { raw_info: { "unionid" => "link_wx_union" } }
    )

    assert_no_difference "User.count" do
      get user_wechat_omniauth_callback_path
    end
    @user.reload
    assert_equal "link_wx_union", @user.weixin_unionid
    assert_equal "link_wx_openid", @user.weixin_web_openid
  end

  test "仅剩 Google 凭据且占位邮箱时解绑被拦截" do
    shell = User.create!(email: "wx_blk@wechat-auto.local", password: "password123", nickname: "壳用户甲")
    identity = shell.identities.create!(provider: "google_oauth2", uid: "blk_g", email: "x@gmail.com")
    sign_in_user(shell)

    assert_no_difference "Identity.count" do
      delete users_identity_path(identity)
    end
    assert_redirected_to users_profile_path
  end

  test "有真实邮箱时允许解绑 Google" do
    identity = @user.identities.create!(provider: "google_oauth2", uid: "ok_g", email: "x@gmail.com")
    sign_in_user(@user)

    assert_difference "Identity.count", -1 do
      delete users_identity_path(identity)
    end
  end

  test "仅剩微信凭据时解绑被拦截" do
    shell = User.create!(email: "wx_blk2@wechat-auto.local", password: "password123", nickname: "壳用户乙")
    shell.update!(weixin_unionid: "blk_u2", weixin_web_openid: "blk_w2")
    sign_in_user(shell)

    delete users_unlink_wechat_path
    assert shell.reload.weixin_unionid.present?
    assert_redirected_to users_profile_path
  end

  test "有真实邮箱时允许解绑微信" do
    @user.update!(weixin_unionid: "ok_u", weixin_web_openid: "ok_w")
    sign_in_user(@user)

    delete users_unlink_wechat_path
    assert_nil @user.reload.weixin_unionid
    assert_nil @user.weixin_web_openid
  end

  private

  def sign_in_user(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def mock_google(uid, email)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: { email: email, name: "绑定测试", image: "https://example.com/g.png" }
    )
  end
end
