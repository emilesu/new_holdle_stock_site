class VerificationMailer < ApplicationMailer
  PURPOSE_COPY = {
    "bind_email" => ["邮箱绑定验证码", "您正在将此邮箱绑定到 HOLD LE 账号"],
    "set_password" => ["设置登录密码验证码", "您正在为 HOLD LE 账号设置登录密码"],
    "reset_password" => ["重置登录密码验证码", "您正在重置 HOLD LE 账号的登录密码"]
  }.freeze

  def code_email(email:, code:, purpose: "bind_email")
    @code = code
    @subject_label, @intro = PURPOSE_COPY.fetch(purpose, PURPOSE_COPY["bind_email"])
    @ttl_minutes = EmailVerificationService::CODE_TTL / 1.minute
    mail to: email, subject: "【HOLD LE】#{@subject_label}"
  end
end
