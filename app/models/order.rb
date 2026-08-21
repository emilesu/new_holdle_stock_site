class Order < ApplicationRecord
  belongs_to :user

  validates :order_no, presence: true, uniqueness: true
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }

  scope :pending, -> { where(status: "pending") }
  scope :paid, -> { where(status: "paid") }

  before_validation :generate_order_no, on: :create
  before_create :set_expire_at

  def paid?
    status == "paid"
  end

  # 支付成功（幂等：已 paid 直接返回，防止微信回调重复触发重复发放）
  def mark_as_paid!(transaction_id:, notify_data:)
    with_lock do
      return if paid?

      update!(
        status: "paid",
        wechat_transaction_id: transaction_id,
        paid_at: Time.current,
        notify_raw: notify_data
      )
      handle_payment!
    end
  end

  def amount_yuan
    amount_cents / 100.0
  end

  private

  # T7 Phase2：按套餐发放 key（1 用户 1 active key）
  def handle_payment!
    plan = Plan.find_by(plan_code: plan_code)
    plan ||= Plan.find_by!(plan_code: "member_permanent") # 历史订单兜底

    if plan.is_member_upgrade
      upgrade_user_to_member!
      grant_or_convert_member_key!
    else
      grant_or_topup_quota_key!(plan)
    end
  end

  # 468：已有 active key → 转无限（key 不变）；无 → 生成会员 key
  def grant_or_convert_member_key!
    key = user.api_keys.active.first
    key ? key.convert_to_member! : ApiKey.generate!(user: user, plan: Plan.find_by!(plan_code: "member_permanent"))
  end

  # 次数包：无 active key → 新建；有 → 加次数（会员无限次 key 跳过，无需加）
  # increment! 用原子 SQL（COALESCE + N）累加，避免并发订单回调 lost update
  def grant_or_topup_quota_key!(plan)
    key = user.api_keys.active.first
    return if key&.unlimited?
    return ApiKey.generate!(user: user, plan: plan) unless key

    key.increment!(:quota_remaining, plan.quota)
  end

  def generate_order_no
    self.order_no ||= begin
      loop do
        no = "HL#{Time.current.strftime('%Y%m%d')}#{SecureRandom.random_number(10**6).to_s.rjust(6, '0')}"
        break no unless Order.exists?(order_no: no)
      end
    end
  end

  def set_expire_at
    self.expire_at ||= 30.minutes.from_now
  end

  def upgrade_user_to_member!
    # 管理员/超管不会被降级（微信回调不经前端拦截，防止 admin 被误降级为 member）
    return if user.is_admin?
    user.update!(role: :member, member_expire_at: 50.years.from_now)
  end
end
