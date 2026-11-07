class ApplicationMailer < ActionMailer::Base
  # 必须与 SMTP 认证账号一致（阿里云企业邮箱要求 From==登录账号），否则 550 拒信
  default from: "no-reply@holdle.com"
  layout "mailer"
end
