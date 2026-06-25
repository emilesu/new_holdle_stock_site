# 发送 Strict-Transport-Security: max-age=0 清除浏览器缓存的 HSTS 记录
# 浏览器接收到此头后会删除该主机名的 HSTS 策略，之后可以安全地通过 HTTP 访问
# 如需恢复 HSTS，删除此文件即可
Rails.application.config.action_dispatch.default_headers.merge!(
  "Strict-Transport-Security" => "max-age=0"
)