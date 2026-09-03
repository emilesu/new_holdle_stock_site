class OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_already_member, only: [:new, :create]
  helper_method :wechat_in_app_browser?

  def new
    @plan = find_purchasable_plan(params[:plan])
    unless @plan
      redirect_to join_path, alert: plan_unavailable_message(params[:plan]) and return
    end
    @order = Order.new
  end

  def create
    plan = find_purchasable_plan(params[:plan])
    unless plan
      redirect_to join_path, alert: plan_unavailable_message(params[:plan]) and return
    end

    # 下单页自选支付方式：alipay → 支付宝（按 UA 区分扫码/手机唤起），否则走微信
    return create_alipay_order(plan) if params[:payment_method] == "alipay"

    payment_method = detect_payment_method

    # JSAPI 支付需要 openid，优先公众号，回退到开放平台
    if payment_method == "wechat_jsapi"
      openid = current_user.weixin_app_openid || current_user.weixin_web_openid
      unless openid
        session[:after_wechat_auth] = "new_order"
        auth_url = user_wechat_mobile_omniauth_authorize_path
        render html: auto_auth_form(auth_url), layout: false
        return
      end
    end

    begin
      order = current_user.orders.create!(
        product_code: plan.plan_code,
        plan_code: plan.plan_code,
        quota: plan.quota,
        title: plan.name,
        amount_cents: plan.price_cents,
        payment_method: payment_method
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[WxPay] Order creation failed: #{e.message}"
      redirect_to new_order_path(plan: plan.plan_code), alert: "订单创建失败，请重试"
      return
    end

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
      wx_params[:openid] = openid
    end

    begin
      result = WxPay::Service.invoke_unifiedorder(wx_params)
    rescue => e
      Rails.logger.error "[WxPay] order #{order.order_no} API error: #{e.class} #{e.message}"
      redirect_to new_order_path(plan: plan.plan_code), alert: "微信支付服务暂时不可用，请稍后重试"
      return
    end

    if result.success?
      if payment_method == "wechat_jsapi"
        order.update(prepay_id: result["prepay_id"])
        redirect_to order_path(order)
      else
        order.update(code_url: result["code_url"])
        redirect_to order_path(order)
      end
    else
      Rails.logger.error "[WxPay] order #{order.order_no} failed: #{result["err_code_des"] || result["return_msg"]}"
      redirect_to new_order_path(plan: plan.plan_code), alert: "订单创建失败：#{result["err_code_des"] || result["return_msg"]}"
    end
  end

  def show
    @order = current_user.orders.find(params[:id])

    if @order.paid?
      # 支付成功落地页：展示 Key + 引导（回调 mark_as_paid! 已确保 Key 就绪）
      @api_key = current_user.api_keys.active.first
      # 明文缺失兜底：老 key 无明文时换新明文，保证落地页可展示/复制（用户从未见过明文，旧明文无副作用）
      @api_key&.regenerate_plaintext! if @api_key&.key_plaintext.blank?
      render :paid
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

  # T7 Phase2：可购买套餐（排除 welcome 赠送档）。
  # 缺省(无 plan 参数) → 主推 member_permanent 468；非法 code 查不到 → 返回 nil（明确报错，不回退高价）
  def find_purchasable_plan(code)
    purchasable = Plan.active.where.not(plan_code: "welcome")
    code.present? ? purchasable.find_by(plan_code: code) : purchasable.find_by(plan_code: "member_permanent")
  end

  def plan_unavailable_message(code)
    code.present? ? "套餐不存在或已下架，请重新选择" : "套餐数据未初始化，请稍后再试"
  end

  def detect_payment_method
    request.user_agent.to_s.include?("MicroMessenger") ? "wechat_jsapi" : "wechat_native"
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

  # ===== 支付宝支付（电脑网站支付 + 手机网站支付）=====

  # 支付宝下单：按 UA 区分通道（手机浏览器→手机网站支付；桌面→电脑网站支付）
  def create_alipay_order(plan)
    unless ALIPAY_CLIENT
      Rails.logger.error "[Alipay] ALIPAY_CLIENT 未配置（缺少 ALIPAY_APP_ID）"
      redirect_to new_order_path(plan: plan.plan_code), alert: "支付宝支付暂未开通，请稍后再试" and return
    end

    payment_method = mobile_ua? ? "alipay_wap" : "alipay_page"

    begin
      order = current_user.orders.create!(
        product_code: plan.plan_code,
        plan_code: plan.plan_code,
        quota: plan.quota,
        title: plan.name,
        amount_cents: plan.price_cents,
        payment_method: payment_method
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[Alipay] Order creation failed: #{e.message}"
      redirect_to new_order_path(plan: plan.plan_code), alert: "订单创建失败，请重试"
      return
    end

    begin
      if payment_method == "alipay_wap"
        # 手机网站支付：唤起支付宝 App（未装则进 H5 收银台）
        url = ALIPAY_CLIENT.page_execute_url(
          method: "alipay.trade.wap.pay",
          return_url: alipay_return_url,
          notify_url: alipay_notify_url,
          biz_content: JSON.generate({
            out_trade_no: order.order_no,
            product_code: "QUICK_WAP_WAY",
            total_amount: format("%.2f", order.amount_yuan),
            subject: order.title,
            quit_url: alipay_return_url
          }, ascii_only: true)
        )
        order.update!(code_url: url)
        # 手机网站支付：服务端直接 302 到支付宝 H5。避免经过需登录的订单页，
        # 微信内「···在浏览器打开」才能直接落在公开的支付宝域名上唤起 App，而非跳 HOLDLE 登录页。
        redirect_to url, allow_other_host: true
      else
        # 电脑网站支付：桌面浏览器跳转支付宝收银台（可扫码或登录账号支付）
        url = ALIPAY_CLIENT.page_execute_url(
          method: "alipay.trade.page.pay",
          return_url: alipay_return_url,
          notify_url: alipay_notify_url,
          biz_content: JSON.generate({
            out_trade_no: order.order_no,
            product_code: "FAST_INSTANT_TRADE_PAY",
            total_amount: format("%.2f", order.amount_yuan),
            subject: order.title
          }, ascii_only: true)
        )
        order.update!(code_url: url)
        redirect_to order_path(order)
      end
    rescue => e
      Rails.logger.error "[Alipay] order #{order&.order_no || "?"} API error: #{e.class} #{e.message}"
      redirect_to new_order_path(plan: plan.plan_code), alert: "支付宝支付服务暂时不可用，请稍后重试"
    end
  end

  def alipay_notify_url
    base = Rails.env.production? ? "https://www.holdle.com" : "http://8.210.33.72:3001"
    "#{base}/alipay/notify"
  end

  def alipay_return_url
    base = Rails.env.production? ? "https://www.holdle.com" : "http://8.210.33.72:3001"
    "#{base}/alipay/return"
  end

  def mobile_ua?
    ua = request.user_agent.to_s.downcase
    ua.match?(/android|iphone|ipad|mobile|micromessenger|alipayclient|ucbrowser/i)
  end

  # 微信内置浏览器（MicroMessenger WebView）：腾讯会拦截支付宝 scheme 与收银台域名，
  # 无法直接唤起支付宝，需引导用户在系统浏览器打开。排除 AlipayClient 以免支付宝回跳场景误判。
  def wechat_in_app_browser?
    ua = request.user_agent.to_s.downcase
    ua.include?("micromessenger") && !ua.include?("alipayclient")
  end

  def auto_auth_form(auth_url)
    <<~HTML.html_safe
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>授权中...</title></head>
      <body>
        <p style="text-align:center;margin-top:40px;font-size:16px;color:#555;">正在跳转微信授权...</p>
        <form id="auth-form" action="#{auth_url}" method="post">
          <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
        </form>
        <script>document.getElementById('auth-form').submit();</script>
      </body>
      </html>
    HTML
  end
end
