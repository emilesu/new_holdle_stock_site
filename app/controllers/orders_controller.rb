class OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_already_member, only: [:new, :create]

  def new
    @product = Order::PRODUCTS["member_permanent"]
    @order = Order.new
  end

  def create
    payment_method = detect_payment_method

    order = current_user.orders.create!(
      product_code: "member_permanent",
      title: Order::PRODUCTS["member_permanent"][:title],
      amount_cents: Order::PRODUCTS["member_permanent"][:amount_cents],
      payment_method: payment_method
    )

    notify_url = wechat_pay_notify_url
    spbill_create_ip = request.remote_ip

    wx_params = {
      body: order.title,
      out_trade_no: order.order_no,
      total_fee: order.amount_cents,
      spbill_create_ip: spbill_create_ip,
      notify_url: notify_url,
      trade_type: payment_method == "wechat_jsapi" ? "JSAPI" : "NATIVE"
    }

    if payment_method == "wechat_jsapi"
      openid = current_user.weixin_app_openid
      unless openid
        redirect_to user_wechat_mobile_omniauth_authorize_path(state: "pay_order_#{order.order_no}")
        return
      end
      wx_params[:openid] = openid
    end

    result = WxPay::Service.invoke_unifiedorder(wx_params)

    if result.success?
      if payment_method == "wechat_jsapi"
        order.update(prepay_id: result["prepay_id"])
        @pay_params = WxPay::Service.generate_js_pay_req(
          prepayid: result["prepay_id"],
          noncestr: SecureRandom.hex(16)
        )
        render :show
      else
        order.update(code_url: result["code_url"])
        redirect_to order_path(order)
      end
    else
      Rails.logger.error "[WxPay] order #{order.order_no} failed: #{result["err_code_des"] || result["return_msg"]}"
      redirect_to new_order_path, alert: "订单创建失败：#{result["err_code_des"] || result["return_msg"]}"
    end
  end

  def show
    @order = current_user.orders.find(params[:id])

    if @order.paid?
      redirect_to root_path, notice: "欢迎加入 HOLD LE！"
    elsif @order.payment_method == "wechat_jsapi"
      # JSAPI 需要重新生成支付参数并渲染页面
      @pay_params = WxPay::Service.generate_js_pay_req(
        prepayid: @order.prepay_id,
        noncestr: SecureRandom.hex(16)
      )
    end
  end

  def status
    @order = current_user.orders.find(params[:id])
    render json: { status: @order.status, paid: @order.paid? }
  end

  private

  def detect_payment_method
    wechat_browser? ? "wechat_jsapi" : "wechat_native"
  end

  def redirect_if_already_member
    if current_user.is_member?
      redirect_to root_path, notice: "你已经是会员了"
    end
  end

  def wechat_pay_notify_url
    base = Rails.env.production? ? "https://www.holdle.com" : "http://8.210.33.72:3001"
    "#{base}/wechat/pay_callbacks"
  end
end
