class ApiKey < ApplicationRecord
  belongs_to :user
  has_many :usage_logs, dependent: :destroy
  has_many :api_key_adjustments, dependent: :destroy

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

  # T7 Phase2：后台调整次数（补偿/退款）。无限次 key 不允许调整，返回 false
  def adjust_quota!(delta:, admin:, reason:)
    return false if unlimited?

    ApiKey.transaction do
      original = quota_remaining
      self.quota_remaining = [quota_remaining + delta, 0].max
      save!
      # 审计记录实际生效的 delta（扣减超剩余时按实扣记录，保证对账准确）
      effective_delta = quota_remaining - original
      ApiKeyAdjustment.create!(api_key: self, user: user, admin: admin, delta: effective_delta, reason: reason)
    end
    true
  end

  # T7 Phase2：停用（可恢复）
  def disable!(reason: nil)
    update!(status: "disabled", disabled_reason: reason)
  end

  # T7 Phase2：启用（恢复）
  def enable!
    update!(status: "active", disabled_reason: nil)
  end

  # T7 Phase2：购买 468 升会员后，把现有 active key 转为无限次（key 不变，用户无感）
  def convert_to_member!
    update!(plan_code: "member_permanent", quota_remaining: nil, quota_total: 0, disabled_reason: nil)
  end
end
