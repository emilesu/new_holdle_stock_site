class Plan < ApplicationRecord
  validates :plan_code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :quota, numericality: { greater_than: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }

  # 无限次套餐（member_permanent 的 quota = nil）
  def unlimited?
    quota.nil?
  end

  def price_yuan
    price_cents / 100.0
  end
end
