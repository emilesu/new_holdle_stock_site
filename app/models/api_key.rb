class ApiKey < ApplicationRecord
  belongs_to :user
  has_many :usage_logs, dependent: :destroy

  validates :key_hash, presence: true, uniqueness: true
  validates :key_prefix, presence: true
  validates :plan_code, presence: true
  validates :status, inclusion: { in: %w[active disabled revoked] }

  scope :active, -> { where(status: "active") }

  # 生成 key（返回明文，仅创建时展示一次；入库存 SHA256 哈希）
  # 决策：每用户 1 个 active key，已有 active key 时不重复生成
  def self.generate!(user:, plan:)
    return nil if user.api_keys.active.exists?

    plain = "hl_" + SecureRandom.hex(8)
    create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11], # "hl_xxxxxxxx"
      user: user,
      plan_code: plan.plan_code,
      quota_remaining: plan.quota, # member_permanent 的 quota=nil → 无限
      quota_total: plan.quota || 0
    )
    plain
  end

  def unlimited?
    quota_remaining.nil?
  end

  def active?
    status == "active"
  end

  def plan_name
    Plan.find_by(plan_code: plan_code)&.name || plan_code
  end

  def decrement_quota!
    return if unlimited?
    update!(quota_remaining: [quota_remaining - 1, 0].max)
  end
end
