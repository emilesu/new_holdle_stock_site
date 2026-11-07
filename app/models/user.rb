class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable, :lockable,
         :omniauthable, omniauth_providers: [:wechat, :wechat_mobile, :google_oauth2]

  # 内容权限阶梯（access_level 与本组常量同义：数值越大要求身份越高）
  TIER_VISITOR = 0 # 访客
  TIER_STUDENT = 1 # 课程学员（268）
  TIER_MEMBER  = 2 # 会员（468）

  enum role: {
    user: "user",
    student: "student",
    member: "member",
    admin: "admin",
    super_admin: "super_admin"
  }, _default: "user"

  validates :nickname, presence: true, length: { in: 2..20 }
  validates :bio, length: { maximum: 500 }, allow_blank: true

  has_many :user_favorites, dependent: :destroy
  has_many :favorite_stocks, through: :user_favorites, source: :stock
  has_many :messages, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :usage_logs, dependent: :destroy
  has_many :api_key_adjustments, dependent: :destroy # 作为 key 持有人
  has_many :identities, dependent: :destroy # 第三方登录凭据（Google 等，PR-3）

  # 自动生成的占位邮箱后缀（微信建号 / 旧站迁移 / 归档），此类邮箱收不到真实邮件
  PLACEHOLDER_EMAIL_SUFFIXES = %w[@wechat-auto.local @holdle.com @invalid.local].freeze

  def email_placeholder?
    !real_email?
  end

  def real_email?
    email.present? && PLACEHOLDER_EMAIL_SUFFIXES.none? { |suffix| email.end_with?(suffix) }
  end

  def wechat_bound?
    weixin_unionid.present? || weixin_web_openid.present? || weixin_app_openid.present?
  end

  def google_identity
    identities.find_by(provider: "google_oauth2")
  end

  # PR-4 解绑守卫：解绑后必须至少保留一种可登录方式
  # （微信凭据 / 其他第三方凭据 / 能收重置邮件的真实邮箱）
  def can_unlink_wechat?
    identities.exists? || real_email?
  end

  def can_unlink_identity?(identity)
    wechat_bound? || real_email? || identities.where.not(id: identity.id).exists?
  end

  # PR-5 归并归档：归档账号禁止登录（数据保留仅供审计）
  def archived?
    archived_at.present?
  end

  def active_for_authentication?
    super && !archived?
  end

  def inactive_message
    archived? ? :archived : super
  end

  # PR-8 审查修复：Devise 邮件（确认/重置/安全通知）改经 solid_queue 异步投递。
  # 同步 deliver_now 叠加 raise_delivery_errors=true 时，SMTP 抖动会直接 500，
  # 注册场景还会留下"账号已建、邮件未发"的脏状态；异步化后失败由队列重试，不阻塞请求
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  # PR-8 安全通知：占位邮箱收不到信，跳过发送（否则 raise_delivery_errors 下 SMTP 退信直接 500）
  def send_email_changed_notification
    return if email_before_last_save.to_s.end_with?(*PLACEHOLDER_EMAIL_SUFFIXES)
    super
  end

  def send_password_change_notification
    return if email.to_s.end_with?(*PLACEHOLDER_EMAIL_SUFFIXES)
    super
  end

  # PR-7 自助归并资格：新注册 7 天内的第三方壳账号（无付费记录）才可发起
  def claim_eligible?
    created_at > 7.days.ago && orders.none? && (email_placeholder? || identities.exists?)
  end

  def favorite?(stock)
    user_favorites.exists?(stock_id: stock.id)
  end

  def favorite!(stock, rating: UserFavorite::DEFAULT_RATING)
    # 已收藏则更新星级（幂等）：星级点击可能在重复提交 / 并发下落到这里，
    # 不应像旧逻辑那样抛唯一性校验异常
    favorite = user_favorites.find_or_initialize_by(stock: stock)
    favorite.rating = rating
    favorite.save!
    favorite
  rescue ActiveRecord::RecordNotUnique
    # 并发下两个请求同时 insert：唯一索引兜底后重读并更新星级
    favorite = user_favorites.find_by!(stock_id: stock.id)
    favorite.update!(rating: rating)
    favorite
  end

  def unfavorite!(stock)
    user_favorites.find_by(stock_id: stock.id)&.destroy
  end

  def is_super_admin?
    role == "super_admin"
  end

  def is_admin?
    role == "admin" || role == "super_admin"
  end

  def is_member?
    return true if role == "admin" || role == "super_admin"
    return false unless role == "member"
    member_expire_at.present? && member_expire_at > Time.current
  end

  def is_user?
    role == "user" && !is_member?
  end

  # 课程学员身份（不含会员：会员用 is_member?，两者判断互不影响存量逻辑）
  def is_student?
    role == "student"
  end

  # 内容访问档位：会员（含管理员）=2，学员=1，其余=0。
  # 内容门控统一用 `user&.content_tier || 0 >= access_level` 比较
  def content_tier
    return TIER_MEMBER if is_member?
    return TIER_STUDENT if is_student?
    TIER_VISITOR
  end

  def was_previously_member?
    previous_role = saved_changes["role"]&.first
    previous_role.in?(%w[member admin super_admin])
  end

  def upgrade_api_key_to_member
    key = api_keys.active.first
    return unless key
    return if key.plan_code == "member_permanent" # 已经是会员套餐，无需升级

    key.convert_to_member!
    Rails.logger.info "[ApiKey] 角色升级自动转会员 key=#{key.id} user=#{id}"
  rescue => e
    Rails.logger.warn "[ApiKey] 升级失败 key=#{key.id} user=#{id}: #{e.message}"
  end

  def downgrade_api_key_to_visitor
    key = api_keys.active.first
    return unless key
    return if key.plan_code == "welcome" # 已经是访客套餐，无需降级

    welcome_plan = Plan.find_by(plan_code: "welcome")
    return unless welcome_plan

    key.update!(plan_code: "welcome", quota_remaining: welcome_plan.quota, quota_total: welcome_plan.quota)
    Rails.logger.info "[ApiKey] 角色降级自动转访客 key=#{key.id} user=#{id}"
  rescue => e
    Rails.logger.warn "[ApiKey] 降级失败 key=#{key.id} user=#{id}: #{e.message}"
  end

  before_save :set_default_member_expire_at
  after_create :grant_initial_api_key
  after_save :upgrade_api_key_to_member, if: -> { saved_change_to_role? && is_member? && !was_previously_member? }
  after_save :downgrade_api_key_to_visitor, if: -> { saved_change_to_role? && !is_member? && was_previously_member? }

  # T7 Phase2：注册即发 key（会员→无限次 / 非会员→welcome 15次），幂等
  def grant_initial_api_key
    plan = Plan.find_by(plan_code: is_member? ? "member_permanent" : "welcome")
    ApiKey.generate!(user: self, plan: plan) if plan
  rescue => e
    Rails.logger.warn "[ApiKey] 注册发 key 失败 user=#{id}: #{e.message}"
  end

  def set_default_member_expire_at
    return unless %w[member admin super_admin].include?(role)

    if member_expire_at.blank?
      self.member_expire_at = 5.years.from_now
    elsif role_changed? && member_expire_at <= Time.current
      # 角色改为会员但沿用了旧的过期时间（后台编辑表单会原样重提旧值）：自动顺延，
      # 否则 is_member? 仍为 false，会员遮罩不会消失（2026-10 Zzz.io 工单根因）
      self.member_expire_at = 5.years.from_now
    end
  end

  def avatar_char
    return "?" if nickname.blank? && email.blank?
    
    char = nickname.present? ? nickname.strip[0] : email.strip[0]
    char =~ /\p{Han}/ ? char : char.upcase
  end

  def member_status
    if is_admin?
      "永久会员"
    elsif is_student?
      "课程学员"
    elsif member_expire_at.present?
      member_expire_at > Time.current ? "会员（#{I18n.l(member_expire_at.to_date)} 到期）" : "会员已过期（#{I18n.l(member_expire_at.to_date)}）"
    else
      "访客"
    end
  end
end
