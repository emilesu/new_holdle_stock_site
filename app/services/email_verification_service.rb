# 邮箱验证码（PR-6）：6 位数字、10 分钟有效、5 次尝试上限、60 秒重发间隔、按 IP 小时限流。
# 只存 BCrypt 摘要不存明文；验证通过即销毁（一次性）。
class EmailVerificationService
  class Error < StandardError; end

  CODE_TTL = 10.minutes
  RESEND_INTERVAL = 60.seconds
  MAX_ATTEMPTS = 5
  IP_HOURLY_LIMIT = 10

  def self.issue(email:, purpose:, ip: nil)
    email = normalize(email)
    recent = EmailVerification.where(email: email, purpose: purpose).order(id: :desc).first
    raise Error, "获取过于频繁，请 60 秒后再试" if recent && recent.created_at > RESEND_INTERVAL.ago

    if ip.present? && EmailVerification.where(ip: ip, created_at: 1.hour.ago..).count >= IP_HOURLY_LIMIT
      raise Error, "验证码请求过多，请稍后再试"
    end

    # 顺带清理一天前的残留记录，防表无界增长（走 created_at 索引）
    EmailVerification.where(created_at: ...1.day.ago).delete_all

    code = format("%06d", SecureRandom.random_number(1_000_000))
    record = EmailVerification.create!(
      email: email, purpose: purpose,
      code_digest: Devise::Encryptor.digest(User, code),
      expires_at: CODE_TTL.from_now, ip: ip
    )
    VerificationMailer.code_email(email: email, code: code).deliver_now
    record
  end

  # 校验通过返回 true；失败抛 Error（尝试超限/过期/错误）
  def self.verify!(email:, purpose:, code:)
    email = normalize(email)
    record = EmailVerification.where(email: email, purpose: purpose).active.order(id: :desc).first
    raise Error, "验证码已过期，请重新获取" if record.nil?
    raise Error, "错误次数过多，请重新获取验证码" if record.attempt_count >= MAX_ATTEMPTS

    unless Devise::Encryptor.compare(User, record.code_digest, code.to_s)
      record.update_column(:attempt_count, record.attempt_count + 1)
      raise Error, "验证码不正确"
    end

    record.destroy!
    true
  end

  def self.normalize(email)
    email.to_s.downcase.strip
  end
end
