require "test_helper"

# PR-3 Google 回调三级解析：provider+uid 精确匹配 → 邮箱兜底自愈 → 新建账号
class GoogleOauthIdentityTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @user = users(:one)
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "uid 凭据命中直接登录且站点邮箱已改也不受影响" do
    @user.identities.create!(provider: "google_oauth2", uid: "g_uid_stable", email: "old@test.com")
    mock_google(uid: "g_uid_stable", email: "changed@gmail.com", name: "Google新名")

    assert_no_difference "User.count" do
      get user_google_oauth2_omniauth_callback_path
    end
    assert_redirected_to root_path
    assert_equal "测试用户一", @user.reload.nickname
  end

  test "邮箱兜底命中老账号时自愈回写凭据" do
    mock_google(uid: "g_uid_first", email: @user.email, name: "Google用户")

    assert_difference "Identity.count", 1 do
      get user_google_oauth2_omniauth_callback_path
    end
    assert_redirected_to root_path
    assert_equal "测试用户一", @user.reload.nickname
    assert_equal "g_uid_first", @user.identities.find_by(provider: "google_oauth2")&.uid
  end

  test "uid 与邮箱均未命中时新建账号并挂凭据" do
    mock_google(uid: "g_uid_brand_new", email: "brand_new@gmail.com", name: "全新谷歌用户")

    assert_difference "User.count", 1 do
      get user_google_oauth2_omniauth_callback_path
    end
    new_user = User.find_by(email: "brand_new@gmail.com")
    assert_not_nil new_user
    assert_equal "全新谷歌用户", new_user.nickname
    assert_equal "g_uid_brand_new", new_user.identities.find_by(provider: "google_oauth2")&.uid
    assert_redirected_to onboarding_path
  end

  test "自愈绑定后改邮箱再次 Google 登录仍进同一账号（复刻空壳号事故场景）" do
    mock_google(uid: "g_uid_relogin", email: @user.email)
    get user_google_oauth2_omniauth_callback_path
    @user.update!(email: "self_changed@holdle.com")

    assert_no_difference "User.count" do
      assert_no_difference "Identity.count" do
        get user_google_oauth2_omniauth_callback_path
      end
    end
  end

  private

  def mock_google(uid:, email:, name: "回归用例Google用户")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, image: "https://example.com/g.png" }
    )
  end
end
