class Wechat::PayCallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    result = Hash.from_xml(request.body.read)["xml"]

    if WxPay::Sign.verify?(result)
      order = Order.find_by!(order_no: result["out_trade_no"])
      return render xml: success_response if order.paid?

      order.mark_as_paid!(
        transaction_id: result["transaction_id"],
        notify_data: result
      )

      Rails.logger.info "[WxPay] Order #{order.order_no} paid successfully"
      render xml: success_response
    else
      Rails.logger.error "[WxPay] callback signature verification failed for #{result["out_trade_no"]}"
      render xml: fail_response
    end
  end

  private

  def success_response
    { return_code: "SUCCESS", return_msg: "OK" }.to_xml(root: "xml", dasherize: false)
  end

  def fail_response
    { return_code: "FAIL", return_msg: "签名失败" }.to_xml(root: "xml", dasherize: false)
  end
end
