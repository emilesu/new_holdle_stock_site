WxPay.appid = ENV["WECHAT_PAY_APP_ID"] || ENV["WECHAT_MOBILE_APP_ID"]
WxPay.key = ENV["WECHAT_PAY_KEY"]
WxPay.mch_id = ENV["WECHAT_PAY_MCH_ID"]
WxPay.debug_mode = false

# 商户证书（优先使用 PEM 格式，兼容 OpenSSL 3.0）
begin
  cert_path = ENV["WECHAT_PAY_CERT_PEM_PATH"].presence
  key_path  = ENV["WECHAT_PAY_KEY_PEM_PATH"].presence

  if cert_path && key_path
    WxPay.apiclient_cert = File.read(cert_path)
    WxPay.apiclient_key  = File.read(key_path)
    Rails.logger.info "[WxPay] 已加载 PEM 证书"
  elsif ENV["WECHAT_PAY_CERT_PATH"].present?
    p12 = File.read(ENV["WECHAT_PAY_CERT_PATH"])
    WxPay.set_apiclient_by_pkcs12(p12, ENV["WECHAT_PAY_MCH_ID"])
    Rails.logger.info "[WxPay] 已加载 PKCS12 证书"
  end
rescue => e
  Rails.logger.warn "[WxPay] 证书加载失败: #{e.message}，支付功能可正常运行，退款功能受限"
end

WxPay.extra_rest_client_options = { timeout: 10, open_timeout: 5 }
