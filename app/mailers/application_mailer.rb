class ApplicationMailer < ActionMailer::Base
  # 必须与 SMTP 认证账号一致（阿里云企业邮箱要求 From 的地址部分==登录账号，显示名可自定义）
  default from: 'HOLD LE <no-reply@holdle.com>'
  layout "mailer"
end
