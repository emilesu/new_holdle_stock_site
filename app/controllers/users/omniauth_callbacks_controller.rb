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

    # PR-4 绑定分支：登录态下从 profile 发起的绑定，把微信凭据挂到当前账号而非走登录匹配。
    # 标记无论是否用上都必须删除，避免残留 session 劫持后续正常登录
    link_mode = session.delete(:identity_link_provider)
    if %w[wechat wechat_mobile].include?(link_mode) && user_signed_in?
      link_wechat_identity(auth, platform)
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
        # 如果 openid 已被其他用户占用，先释放（兼容同一人分别在扫码和公众号各有一个账号的情况）
        other = User.find_by(openid_field => open_id)
        if other && other.id != user.id
          other.update(openid_field => nil)
          Rails.logger.info "[OmniAuth WeChat] released #{openid_field}=#{open_id} from user #{other.id} to user #{user.id}"
        end
        updates = { nickname: wx_nickname, avatar: wx_avatar, openid_field => open_id }
        user.update(updates)
        sign_in user
        redirect_after_wechat_auth("微信登录成功")
        return
      end
    end

    # 2. 用对应平台的 openid 匹配（兼容已有用户）
    user = User.find_by(openid_field => open_id)

    if user.present?
      # 如果 unionid 已被其他用户占用，先释放
      if union_id.present?
        other = User.find_by(weixin_unionid: union_id)
        if other && other.id != user.id
          other.update(weixin_unionid: nil)
          Rails.logger.info "[OmniAuth WeChat] released unionid=#{union_id} from user #{other.id} to user #{user.id}"
        end
      end
      user.update(
        weixin_unionid: union_id,
        nickname: wx_nickname,
        avatar: wx_avatar
      )
      sign_in user
      redirect_after_wechat_auth("微信登录成功，已同步账号信息")
      return
    end

    # 2.5 启发式合并已于 2026-11 退役（PR-1 止血）：
    #     旧站迁移遗留的「按昵称/头像猜同一人」自动合并曾可能误并他人账号，
    #     且会员转移路径会 destroy! 旧账号、级联删除订单/收藏/消息。
    #     现在只做 unionid/openid 精确匹配；疑似同一人仅记日志，
    #     由 admin「合并用户」工具（PR-5）人工核实处理。
    if union_id.present? && wx_nickname.present?
      suspects = User.where(weixin_unionid: nil, weixin_app_openid: nil, weixin_web_openid: nil)
                     .where("nickname = ?", wx_nickname)
      if suspects.exists?
        Rails.logger.warn "[WeChat Suspect] 同名无凭据老账号待人工核实 ids=#{suspects.limit(5).pluck(:id).join(',')} nickname=#{wx_nickname} unionid=#{union_id}"
      end
    end

    # 3. 无匹配 → 新建微信账号
    temp_email = "wx_#{open_id}@wechat-auto.local"
    random_pw = Devise.friendly_token(20)
    create_attrs = {
      email: temp_email,
      password: random_pw,
      nickname: wx_nickname.to_s.length >= 2 ? wx_nickname : "微信用户",
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
    Rails.logger.info "[WeChat New] 新建微信账号 id=#{user.id} platform=#{platform} unionid=#{union_id}"
    redirect_after_wechat_auth("微信注册并登录成功", new_user: true)
  end

  def redirect_after_wechat_auth(notice, new_user: false)
    if session[:after_wechat_auth] == "new_order"
      session.delete(:after_wechat_auth)
      # 下单流程中注册的新用户：先完成支付，引导延后（直接视为已完成引导，避免被兜底守卫拦截下单）
      current_user.update!(onboarded_at: Time.current) if new_user && current_user.onboarded_at.blank?
      redirect_to new_order_path, notice: "已授权，请重新点击微信支付"
    elsif new_user
      # 微信新注册用户：带了来源页（return_to）就回来源页，否则先进注册引导页
      redirect_to stored_location_for(:user) || onboarding_path, notice: notice
    else
      # 回到登录前所在页面（无来源页则回首页）
      redirect_to stored_location_for(:user) || root_path, notice: notice
    end
  end

  # PR-4 绑定分支：把 Google 凭据挂到当前登录账号（Users::IdentitiesController#link 发起）
  def link_google_identity(auth)
    me = current_user
    uid = auth.uid.to_s
    email = auth.info.email

    existing = Identity.find_by(provider: "google_oauth2", uid: uid)
    owner = email.present? ? User.where.not(id: me.id).find_by(email: email) : nil

    if existing&.user_id == me.id
      redirect_to users_profile_path, notice: "该 Google 账号已绑定"
    elsif existing || owner
      # 凭据或邮箱已归属他人：直接挂过来会顶掉对方的 Google 登录入口，必须人工处理
      Rails.logger.warn "[Identity Link] google uid=#{uid} email=#{email} 已被占用 existing=#{existing&.user_id} owner=#{owner&.id} by=#{me.id}"
      redirect_to users_profile_path, alert: "该 Google 账号已归属另一个 HOLDLE 账号，如需处理请联系站长"
    elsif me.identities.exists?(provider: "google_oauth2")
      redirect_to users_profile_path, alert: "您已绑定过 Google 账号，如需换绑请先解绑"
    else
      me.identities.create!(provider: "google_oauth2", uid: uid, email: email)
      redirect_to users_profile_path, notice: "Google 账号绑定成功"
    end
  end

  # PR-4 绑定分支：把微信凭据挂到当前登录账号
  def link_wechat_identity(auth, platform)
    me = current_user
    open_id = auth.uid
    union_id = auth.extra.raw_info["unionid"]
    openid_field = (platform == :app) ? :weixin_app_openid : :weixin_web_openid

    taken = User.where.not(id: me.id).exists?(openid_field => open_id) ||
            (union_id.present? && User.where.not(id: me.id).exists?(weixin_unionid: union_id))
    if taken
      Rails.logger.warn "[Identity Link] wechat openid=#{open_id} unionid=#{union_id} 已被占用 by=#{me.id}"
      redirect_to users_profile_path, alert: "该微信已绑定另一个 HOLDLE 账号，如需处理请联系站长"
    elsif me.send(openid_field) == open_id
      redirect_to users_profile_path, notice: "该微信已绑定"
    elsif me.weixin_unionid.present? && union_id.present? && me.weixin_unionid != union_id
      redirect_to users_profile_path, alert: "您已绑定过其他微信，如需换绑请先解绑"
    else
      attrs = { openid_field => open_id }
      attrs[:weixin_unionid] = union_id if union_id.present? && me.weixin_unionid.blank?
      me.update!(attrs)
      redirect_to users_profile_path, notice: "微信绑定成功"
    end
  end

  public

  def google_oauth2
    auth = request.env["omniauth.auth"]
    unless auth
      Rails.logger.error "[OmniAuth Google] auth hash is nil"
      redirect_to new_user_session_path, alert: "Google授权失败：未获取到认证信息"
      return
    end

    # PR-4 绑定分支（与微信同理：标记必删，防残留 session 劫持正常登录）
    link_mode = session.delete(:identity_link_provider)
    if link_mode == "google_oauth2" && user_signed_in?
      link_google_identity(auth)
      return
    end

    uid = auth.uid.to_s
    email = auth.info.email
    g_name = auth.info.name&.truncate(20)
    g_avatar = auth.info.image

    Rails.logger.info "[OmniAuth Google] uid=#{uid} email=#{email}"

    # 三级解析（PR-3）：
    # 1. provider+uid 精确匹配——凭据跟着账号走，站点邮箱或 Google 邮箱变化都不再产生重复空壳号
    user = Identity.find_by(provider: "google_oauth2", uid: uid)&.user

    # 2. 邮箱兜底匹配：命中老账号则回写凭据（自愈）。
    #    历史 Google 用户从未存过 uid，靠这一步在首次登录时绑定；此后改邮箱不再丢号
    if user.nil? && email.present?
      user = User.find_by(email: email)
      if user
        identity = user.identities.create(provider: "google_oauth2", uid: uid, email: email)
        Rails.logger.info "[OmniAuth Google] identity self-heal user=#{user.id} uid=#{uid} created=#{identity.persisted?}"
        # 仅补空头像，绝不覆盖用户自设昵称（旧逻辑每次登录都用 Google 昵称冲掉站点昵称）
        user.update(avatar: g_avatar) if g_avatar.present? && user.avatar.blank?
      end
    end

    # 3. 无匹配 → 新建账号 + 凭据
    if user.nil?
      user = User.create(
        email: email,
        password: Devise.friendly_token(20),
        nickname: g_name.presence || "Google用户",
        role: "user",
        avatar: g_avatar
      )

      unless user.persisted?
        Rails.logger.error "[OmniAuth Google] user creation failed: #{user.errors.full_messages}"
        redirect_to new_user_session_path, alert: "Google注册失败：#{user.errors.full_messages.first}"
        return
      end

      user.identities.create(provider: "google_oauth2", uid: uid, email: email)
      Rails.logger.info "[OmniAuth Google] new user created id=#{user.id}"
      sign_in user
      redirect_to stored_location_for(:user) || onboarding_path, notice: "Google注册登录成功"
      return
    end

    sign_in user
    redirect_to stored_location_for(:user) || root_path, notice: "Google登录成功"
  end

  def failure
    strategy_name = request.env["omniauth.error.strategy"]&.name || "unknown"
    error_type = request.env["omniauth.error.type"]
    error_message = request.env["omniauth.error"]&.message
    Rails.logger.error "[OmniAuth Failure] strategy=#{strategy_name} type=#{error_type} error=#{error_message}"
    redirect_to new_user_session_path, alert: "授权失败（#{strategy_name}），请重试"
  end
end