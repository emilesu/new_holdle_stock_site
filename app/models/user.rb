class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:wechat, :wechat_mobile, :google_oauth2]

  enum role: {
    user: "user",
    member: "member",
    admin: "admin",
    super_admin: "super_admin"
  }, _default: "user"

  validates :nickname, presence: true, length: { in: 2..20 }
  validates :bio, length: { maximum: 500 }, allow_blank: true

  has_many :user_favorites, dependent: :destroy
  has_many :favorite_stocks, through: :user_favorites, source: :stock
  has_many :message_boards, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :usage_logs, dependent: :destroy
  has_many :api_key_adjustments, dependent: :destroy # 作为 key 持有人

  # 谷歌登录账号匹配创建
  def self.find_for_google_oauth(auth)
    user = find_by(email: auth.info.email)
    return user if user

    create!(
      email: auth.info.email,
      password: Devise.friendly_token[0, 20],
      nickname: auth.info.name,
      role: 'user'
    )
  end

  def favorite?(stock)
    user_favorites.exists?(stock_id: stock.id)
  end

  def favorite!(stock)
    user_favorites.create!(stock: stock)
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
    return unless member_expire_at.blank?
    return unless %w[member admin super_admin].include?(role)
    self.member_expire_at = 5.years.from_now
  end

  def avatar_char
    return "?" if nickname.blank? && email.blank?
    
    char = nickname.present? ? nickname.strip[0] : email.strip[0]
    char =~ /\p{Han}/ ? char : char.upcase
  end

  def member_status
    if is_admin?
      "永久会员"
    elsif member_expire_at.present?
      member_expire_at > Time.current ? "会员（#{I18n.l(member_expire_at.to_date)} 到期）" : "会员已过期（#{I18n.l(member_expire_at.to_date)}）"
    else
      "访客"
    end
  end
end
