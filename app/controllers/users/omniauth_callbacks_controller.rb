class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def wechat
    auth = request.env["omniauth.auth"]
    open_id = auth.uid
    union_id = auth.extra.raw_info["unionid"]
    wx_nickname = auth.info.nickname&.truncate(30)
    wx_avatar = auth.info.image

    # 1. 查找迁移过来的老用户（用openid匹配weixin_web_openid）
    user = User.find_by(weixin_web_openid: open_id)

    if user.present?
      # 老用户：回填unionid，更新最新头像昵称
      user.update(
        weixin_unionid: union_id,
        nickname: wx_nickname,
        avatar: wx_avatar
      )
      sign_in user
      redirect_to root_path, notice: "微信登录成功，已同步账号信息"
      return
    end

    # 2. 无匹配老用户 → 新建微信账号
    temp_email = "wx_#{open_id}@wechat-auto.local"
    random_pw = Devise.friendly_token(20)
    user = User.create(
      email: temp_email,
      password: random_pw,
      nickname: wx_nickname.presence || "微信用户",
      role: "user",
      avatar: wx_avatar,
      weixin_web_openid: open_id,
      weixin_unionid: union_id,
      weixin_app_openid: nil
    )
    sign_in user
    redirect_to root_path, notice: "微信注册并登录成功"
  end

  def google_oauth2
    auth = request.env["omniauth.auth"]
    email = auth.info.email
    g_name = auth.info.name&.truncate(30)
    g_avatar = auth.info.image

    # 用邮箱匹配老用户（本次迁移有email的用户直接绑定）
    user = User.find_by(email: email)

    if user.present?
      user.update(nickname: g_name, avatar: g_avatar)
      sign_in user
      redirect_to root_path, notice: "Google登录成功"
      return
    end

    # 无邮箱匹配则新建账号
    random_pw = Devise.friendly_token(20)
    user = User.create(
      email: email,
      password: random_pw,
      nickname: g_name.presence || "Google用户",
      role: "user",
      avatar: g_avatar
    )
    sign_in user
    redirect_to root_path, notice: "Google注册登录成功"
  end

  def failure
    redirect_to new_user_session_path, alert: "微信授权失败，请重试"
  end
end