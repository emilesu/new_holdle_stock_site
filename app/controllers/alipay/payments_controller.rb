class Alipay::PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # 支付宝异步通知（native 扫码 / wap 唤起共用）。验签通过且交易成功才标记到账，返回纯文本 success。
  def notify
    unless ALIPAY_CLIENT
      Rails.logger.error "[Alipay] notify: ALIPAY_CLIENT 未配置"
      return render plain: "failure"
    end

    params_hash = request.request_parameters
    return render plain: "failure" unless ALIPAY_CLIENT.verify?(params_hash)

    app_id = params_hash["app_id"]
    out_trade_no = params_hash["out_trade_no"]
    order = Order.find_by(order_no: out_trade_no)

    unless order && app_id == ENV["ALIPAY_APP_ID"]
      Rails.logger.error "[Alipay] notify: order=#{out_trade_no} 不存在或 app_id=#{app_id} 不匹配"
      return render plain: "failure"
    end

    if params_hash["total_amount"].to_f != order.amount_yuan
      Rails.logger.error "[Alipay] notify: order #{out_trade_no} 金额不匹配 回调=#{params_hash["total_amount"]} 订单=#{order.amount_yuan}"
      return render plain: "failure"
    end

    return render plain: "success" if order.paid?

    if %w[TRADE_SUCCESS TRADE_FINISHED].include?(params_hash["trade_status"])
      order.mark_as_paid!(
        transaction_id: params_hash["trade_no"],
        notify_data: params_hash
      )
      Rails.logger.info "[Alipay] Order #{order.order_no} paid successfully"
      render plain: "success"
    else
      # 其它状态（WAIT_BUYER_PAY / TRADE_CLOSED 等）不处理，返回 success 停止重试
      render plain: "success"
    end
  end

  # 支付宝同步跳转（native/wap 共用）。仅做 UX 跳转，到账以 notify + 订单页轮询为准。
  def return_url
    # 只要 out_trade_no 能查到订单就先跳订单页（验签仅作 UX，不应因验签失败阻断跳转），
    # 避免无参回退到默认 468 永久会员下单页。
    if (order = Order.find_by(order_no: params["out_trade_no"]))
      # 已登录（桌面/普通手机浏览器）→ 跳订单页看 Key；微信内「在浏览器打开」支付的用户在
      # 系统浏览器无 session，跳订单页会被 authenticate_user! 拦截，改渲染公开的结果页。
      return redirect_to order_path(order) if user_signed_in?

      @order = order
      render :result
      return
    end

    # 查不到订单（如页面过期/手动访问）→ 跳套餐页，杜绝 new_order_path 无 plan 回退高价
    redirect_to plans_path, alert: "支付结果确认中，请稍后在订单页查看"
  end
end