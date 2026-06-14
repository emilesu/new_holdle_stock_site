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

  has_many :favorite_stocks, dependent: :destroy
  has_many :stocks, through: :favorite_stocks
  has_many :payment_records, dependent: :nullify

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

  def avatar_char
    return "?" if nickname.blank? && email.blank?
    
    char = nickname.present? ? nickname.strip[0] : email.strip[0]
    char =~ /\p{Han}/ ? char : char.upcase
  end

  def member_status
    if is_admin?
      "永久会员"
    elsif member_expire_at.present?
      member_expire_at > Time.current ? "会员（#{l(member_expire_at.to_date)} 到期）" : "会员已过期（#{l(member_expire_at.to_date)}）"
    else
      "普通用户"
    end
  end
end
