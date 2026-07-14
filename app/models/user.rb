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

  # 微信三字段匹配优先级：unionid > web_openid（兼容旧用户）
  def self.find_for_wechat_oauth(auth)
    unionid = auth.extra.raw_info['unionid']
    web_openid = auth.uid

    # 1. 优先通过UnionID匹配已有账号
    if unionid.present?
      user = find_by(weixin_unionid: unionid)
      if user
        # 旧用户仅存web_openid，自动补齐unionid
        if user.weixin_web_openid != web_openid
          user.update(weixin_web_openid: web_openid, weixin_unionid: unionid)
        end
        return user
      end
    end

    # 2. UnionID为空/无匹配，用旧web_openid兼容历史迁移用户
    user = find_by(weixin_web_openid: web_openid)
    if user && unionid.present?
      # 登录自动补齐unionid，完成账号打通
      user.update(weixin_unionid: unionid)
      return user
    end

    # 3. 全新微信用户，创建账号
    create!(
      email: "#{web_openid}@wx-auto.auto",
      password: Devise.friendly_token[0, 20],
      nickname: auth.info.nickname,
      weixin_unionid: unionid,
      weixin_web_openid: web_openid,
      role: 'user'
    )
  end

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

  before_save :set_default_member_expire_at

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
