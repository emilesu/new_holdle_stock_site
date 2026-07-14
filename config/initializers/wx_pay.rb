WxPay.appid = ENV["WECHAT_PAY_APP_ID"] || ENV["WECHAT_MOBILE_APP_ID"]
WxPay.key = ENV["WECHAT_PAY_KEY"]
WxPay.mch_id = ENV["WECHAT_PAY_MCH_ID"]
WxPay.debug_mode = false

# 商户证书（APIv2 使用 PKCS12）
if ENV["WECHAT_PAY_CERT_PATH"].present?
  p12 = File.read(ENV["WECHAT_PAY_CERT_PATH"])
  WxPay.set_apiclient_by_pkcs12(p12, ENV["WECHAT_PAY_MCH_ID"])
end

WxPay.extra_rest_client_options = { timeout: 10, open_timeout: 5 }
