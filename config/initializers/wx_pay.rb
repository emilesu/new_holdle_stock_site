WxPay.appid = ENV["WECHAT_PAY_APP_ID"] || ENV["WECHAT_MOBILE_APP_ID"]
WxPay.key = ENV["WECHAT_PAY_KEY"]
WxPay.mch_id = ENV["WECHAT_PAY_MCH_ID"]
WxPay.debug_mode = false

# 商户证书（APIv2 使用 PKCS12）
# 证书加载失败不阻塞启动，支付回调签名用 API Key 验证即可
if ENV["WECHAT_PAY_CERT_PATH"].present?
  begin
    p12 = File.read(ENV["WECHAT_PAY_CERT_PATH"])
    WxPay.set_apiclient_by_pkcs12(p12, ENV["WECHAT_PAY_MCH_ID"])
  rescue => e
    Rails.logger.warn "[WxPay] 证书加载失败: #{e.message}，支付功能可正常运行，退款功能受限"
  end
end

WxPay.extra_rest_client_options = { timeout: 10, open_timeout: 5 }
