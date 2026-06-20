class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

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
  has_many :payment_records, dependent: :nullify

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
    role == "member" || role == "admin" || role == "super_admin" || (member_expire_at.present? && member_expire_at > Time.current)
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
      "普通用户"
    end
  end
end
