class VerificationMailer < ApplicationMailer
  def code_email(email:, code:)
    @code = code
    @ttl_minutes = EmailVerificationService::CODE_TTL / 1.minute
    mail to: email, subject: "【HOLD LE】邮箱验证码"
  end
end
