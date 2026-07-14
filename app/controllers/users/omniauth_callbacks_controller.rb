class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # 跳过 CSRF 验证（OAuth 回调由外部服务发起，无法携带 CSRF token）
  skip_before_action :verify_authenticity_token, only: [:google_oauth2, :wechat, :wechat_mobile]

  def wechat
    process_wechat_oauth(:web)
  end

  def wechat_mobile
    process_wechat_oauth(:app)
  end

  private

  def process_wechat_oauth(platform)
    auth = request.env["omniauth.auth"]
    unless auth
      Rails.logger.error "[OmniAuth WeChat] auth hash is nil"
      redirect_to new_user_session_path, alert: "微信授权失败：未获取到认证信息"
      return
    end

    open_id = auth.uid
    union_id = auth.extra.raw_info["unionid"]
    wx_nickname = auth.info.nickname&.truncate(20)
    wx_avatar = auth.info.image

    openid_field = (platform == :app) ? :weixin_app_openid : :weixin_web_openid

    Rails.logger.info "[OmniAuth WeChat] platform=#{platform} open_id=#{open_id} union_id=#{union_id}"

    # 1. 优先用 unionid 匹配（跨平台统一识别，公众号+开放平台共享同一 unionid）
    if union_id.present?
      user = User.find_by(weixin_unionid: union_id)
      if user.present?
        updates = { nickname: wx_nickname, avatar: wx_avatar, openid_field => open_id }
        user.update(updates)
        sign_in user
        redirect_to root_path, notice: "微信登录成功"
        return
      end
    end

    # 2. 用对应平台的 openid 匹配（兼容已有用户）
    user = User.find_by(openid_field => open_id)

    if user.present?
      user.update(
        weixin_unionid: union_id,
        nickname: wx_nickname,
        avatar: wx_avatar
      )
      sign_in user
      redirect_to root_path, notice: "微信登录成功，已同步账号信息"
      return
    end

    # 3. 无匹配 → 新建微信账号
    temp_email = "wx_#{open_id}@wechat-auto.local"
    random_pw = Devise.friendly_token(20)
    create_attrs = {
      email: temp_email,
      password: random_pw,
      nickname: wx_nickname.presence || "微信用户",
      role: "user",
      avatar: wx_avatar,
      openid_field => open_id,
      weixin_unionid: union_id
    }
    create_attrs[:weixin_app_openid] = nil if platform == :web
    create_attrs[:weixin_web_openid] = nil if platform == :app

    user = User.create(create_attrs)

    unless user.persisted?
      Rails.logger.error "[OmniAuth WeChat] user creation failed: #{user.errors.full_messages}"
      redirect_to new_user_session_path, alert: "微信注册失败：#{user.errors.full_messages.first}"
      return
    end

    sign_in user
    redirect_to root_path, notice: "微信注册并登录成功"
  end

  public

  def google_oauth2

  def google_oauth2
    auth = request.env["omniauth.auth"]
    unless auth
      Rails.logger.error "[OmniAuth Google] auth hash is nil"
      redirect_to new_user_session_path, alert: "Google授权失败：未获取到认证信息"
      return
    end

    email = auth.info.email
    g_name = auth.info.name&.truncate(20)
    g_avatar = auth.info.image

    Rails.logger.info "[OmniAuth Google] email=#{email} name=#{g_name}"

    # 用邮箱匹配老用户（本次迁移有email的用户直接绑定）
    user = User.find_by(email: email)

    if user.present?
      Rails.logger.info "[OmniAuth Google] existing user found id=#{user.id}"
      # update 可能因 nickname 验证失败而返回 false，不影响 sign_in
      result = user.update(nickname: g_name, avatar: g_avatar)
      Rails.logger.info "[OmniAuth Google] user update result=#{result} errors=#{user.errors.full_messages}" unless result

      # sign_in 后验证 session 是否已正确设置
      sign_in user
      Rails.logger.info "[OmniAuth Google] sign_in completed, session user_id=#{session['warden.user.user.key']&.first&.first}"
      redirect_to root_path, notice: "Google登录成功"
    else
      # 无邮箱匹配则新建账号
      random_pw = Devise.friendly_token(20)
      user = User.create(
        email: email,
        password: random_pw,
        nickname: g_name.presence || "Google用户",
        role: "user",
        avatar: g_avatar
      )

      unless user.persisted?
        Rails.logger.error "[OmniAuth Google] user creation failed: #{user.errors.full_messages}"
        redirect_to new_user_session_path, alert: "Google注册失败：#{user.errors.full_messages.first}"
        return
      end

      Rails.logger.info "[OmniAuth Google] new user created id=#{user.id}"
      sign_in user
      Rails.logger.info "[OmniAuth Google] sign_in completed, session user_id=#{session['warden.user.user.key']&.first&.first}"
      redirect_to root_path, notice: "Google注册登录成功"
    end
  end

  def failure
    strategy_name = request.env["omniauth.error.strategy"]&.name || "unknown"
    error_type = request.env["omniauth.error.type"]
    error_message = request.env["omniauth.error"]&.message
    Rails.logger.error "[OmniAuth Failure] strategy=#{strategy_name} type=#{error_type} error=#{error_message}"
    redirect_to new_user_session_path, alert: "授权失败（#{strategy_name}），请重试"
  end
end