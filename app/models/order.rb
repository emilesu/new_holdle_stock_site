class Order < ApplicationRecord
  belongs_to :user

  validates :order_no, presence: true, uniqueness: true
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }

  scope :pending, -> { where(status: "pending") }
  scope :paid, -> { where(status: "paid") }

  PRODUCTS = {
    "member_permanent" => { title: "HOLD LE 永久会员", amount_cents: 46800 }
  }.freeze

  before_validation :generate_order_no, on: :create
  before_create :set_expire_at

  def paid?
    status == "paid"
  end

  def mark_as_paid!(transaction_id:, notify_data:)
    update!(
      status: "paid",
      wechat_transaction_id: transaction_id,
      paid_at: Time.current,
      notify_raw: notify_data
    )
    upgrade_user_to_member!
  end

  def amount_yuan
    amount_cents / 100.0
  end

  private

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
    user.update!(role: :member, member_expire_at: 50.years.from_now)
  end
end
