# 支付宝「手机网站支付」(alipay.trade.wap.pay) 生成的是 openapi.alipay.com 网关 URL，
# 浏览器访问后支付宝会 302 跳转到真正的 H5 收银台 mclient.alipay.com。
# 微信内置浏览器会拦截 openapi.alipay.com 域名（显示「请长按网址复制后使用浏览器访问」），
# 但不拦截 mclient.alipay.com。因此服务端先请求网关并跟随重定向，拿到 mclient 最终地址，
# 再让浏览器直接跳 mclient，从而在微信内也能正常唤起支付宝。
class AlipayWapResolver
  MAX_HOPS = 5
  TIMEOUT = ENV.fetch("ALIPAY_RESOLVE_TIMEOUT", 8).to_i
  MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148".freeze

  # 返回最终收银台地址；任何异常/超时/非重定向一律回退原网关 URL，保证非微信环境仍可用。
  def self.resolve(gateway_url, user_agent: nil)
    ua = user_agent.presence || MOBILE_UA
    current = gateway_url

    MAX_HOPS.times do
      response = Faraday.get(current) do |req|
        req.headers["User-Agent"] = ua
        req.headers["Accept"] = "text/html,application/xhtml+xml"
        req.options.timeout = TIMEOUT
        req.options.open_timeout = TIMEOUT
      end

      if response.status.to_i.between?(300, 399)
        loc = response.headers["location"]
        return gateway_url if loc.blank?
        current = URI.join(current, loc).to_s
      else
        break
      end
    end

    current
  rescue StandardError => e
    Rails.logger.error "[Alipay] WapResolver 解析收银台失败：#{e.class} #{e.message}"
    gateway_url
  end
end