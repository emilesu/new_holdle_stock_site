class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: {
    user: "user",
    member: "member",
    admin: "admin",
    super_admin: "super_admin"
  }, _default: "user"

  def active_member?
    member_expire_at.present? && member_expire_at > Time.current
  end

  def is_admin?
    admin? || super_admin?
  end

  def avatar_char
    (nickname.presence || email).first.upcase
  end
end