# 支付宝客户端（订单码扫码 + 手机网站支付），RSA2 签名
#
# 密钥说明：
# - ALIPAY_APP_PRIVATE_KEY：应用私钥（自己生成，PEM 格式，须带 -----BEGIN ... PRIVATE KEY----- 头尾）
# - ALIPAY_PUBLIC_KEY：支付宝公钥（开放平台后台复制，后台给的是无头尾的裸字符串，这里自动转成 PEM）

# 把无 BEGIN/END 头尾的裸 base64 密钥归一化为 OpenSSL 可解析的 PEM 格式
def alipay_wrap_bare_key(raw, type: "PUBLIC KEY")
  raw = raw.to_s.strip
  return raw if raw.include?("-----BEGIN")
  body = raw.gsub(/\s+/, "").scan(/.{64}|.+/).join("\n")
  "-----BEGIN #{type}-----\n#{body}\n-----END #{type}-----"
end

# 应用私钥可以是裸 PKCS1/PKCS8 base64，自动尝试两种 PEM 头包装
def alipay_normalize_private_key(raw)
  raw = raw.to_s.strip
  return raw if raw.blank? || raw.include?("-----BEGIN")
  ["RSA PRIVATE KEY", "PRIVATE KEY"].each do |header|
    pem = alipay_wrap_bare_key(raw, type: header)
    begin
      OpenSSL::PKey::RSA.new(pem) && (return pem)
    rescue OpenSSL::PKey::RSAError
      next
    end
  end
  raise ArgumentError, "ALIPAY_APP_PRIVATE_KEY 无法解析为 RSA 私钥，请确认是 RSA2 生成的应用私钥"
end

ALIPAY_CLIENT = if ENV["ALIPAY_APP_ID"].present?
  Alipay::Client.new(
    url: ENV["ALIPAY_GATEWAY"] || "https://openapi.alipay.com/gateway.do",
    app_id: ENV["ALIPAY_APP_ID"],
    app_private_key: alipay_normalize_private_key(ENV["ALIPAY_APP_PRIVATE_KEY"]),
    alipay_public_key: alipay_wrap_bare_key(ENV["ALIPAY_PUBLIC_KEY"], type: "PUBLIC KEY")
  )
end