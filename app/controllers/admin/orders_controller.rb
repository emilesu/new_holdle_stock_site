class Admin::OrdersController < Admin::BaseController

  def index
    @orders = Order.joins(:user).includes(:user).order(created_at: :desc)

    # 筛选（全部可空，非法值忽略）
    @orders = @orders.where(status: params[:status]) if params[:status].present? && %w[pending paid].include?(params[:status])
    @orders = @orders.where(plan_code: params[:plan_code]) if params[:plan_code].present?
    @orders = @orders.where(payment_method: params[:payment_method]) if params[:payment_method].present? && %w[wechat_native wechat_jsapi alipay_native alipay_wap].include?(params[:payment_method])

    if params[:q].present?
      q = "%#{params[:q].strip}%"
      @orders = @orders.where("orders.order_no ILIKE ? OR orders.wechat_transaction_id ILIKE ? OR orders.alipay_trade_no ILIKE ? OR users.nickname ILIKE ?", q, q, q, q)
    end

    if params[:from].present? && valid_date?(params[:from])
      @orders = @orders.where("orders.created_at >= ?", Date.parse(params[:from]).beginning_of_day)
    end
    if params[:to].present? && valid_date?(params[:to])
      @orders = @orders.where("orders.created_at <= ?", Date.parse(params[:to]).end_of_day)
    end

    # 统计卡片（与筛选联动）
    @total_count = @orders.count
    @paid_count = @orders.where(status: "paid").count
    @pending_count = @orders.where(status: "pending").count
    @total_amount_cents = @orders.where(status: "paid").sum(:amount_cents)

    @plans = Plan.order(:price_cents)
    @plans_by_code = Plan.all.index_by(&:plan_code)
    @orders = @orders.page(params[:page]).per(50)
  end

  def show
    @order = Order.includes(:user).find(params[:id])
    @api_key = @order.user.api_keys.active.first
  end

  private

  def valid_date?(str)
    Date.parse(str)
    true
  rescue ArgumentError
    false
  end
end
