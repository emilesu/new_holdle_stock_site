# PR-6 绑定/换绑真实邮箱：验证码即时生效（reconfirmable 已关闭，不走双重链接）。
# 占位邮箱账号在此流程可同步首设密码——登录态 + 新邮箱验证码即所有权证明，免 current_password。
class Users::EmailBindingsController < ApplicationController
  before_action :authenticate_user!

  def create
    email = EmailVerificationService.normalize(params[:email])

    unless email.match?(Devise.email_regexp)
      redirect_to users_profile_path, alert: "邮箱格式不正确" and return
    end
    if User.exists?(email: email)
      redirect_to users_profile_path, alert: "该邮箱已被其他账号使用，请确认后重试或联系站长" and return
    end

    session[:binding_email] = email
    EmailVerificationService.issue(email: email, purpose: "bind_email", ip: request.remote_ip)
    redirect_to users_profile_path, notice: "验证码已发送至 #{email}，10 分钟内有效"
  rescue EmailVerificationService::Error => e
    session.delete(:binding_email)
    redirect_to users_profile_path, alert: e.message
  rescue Net::SMTPError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
    # 验证码邮件为同步发送（非 Devise 通知链路），SMTP 故障时给出友好提示而非 500
    session.delete(:binding_email)
    Rails.logger.error "[EmailBinding] 验证码邮件投递失败: #{e.class}: #{e.message}"
    redirect_to users_profile_path, alert: "邮件服务暂时不可用，请稍后再试"
  end

  def update
    email = session[:binding_email]
    if email.blank?
      redirect_to users_profile_path, alert: "请先获取验证码" and return
    end

    EmailVerificationService.verify!(email: email, purpose: "bind_email", code: params[:code])

    attrs = { email: email, confirmed_at: Time.current }
    if params[:password].present?
      attrs[:password] = params[:password]
      attrs[:password_confirmation] = params[:password_confirmation]
    end
    current_user.update!(attrs)
    session.delete(:binding_email)
    bypass_sign_in(current_user)
    redirect_to users_profile_path, notice: params[:password].present? ? "邮箱绑定成功，密码已设置" : "邮箱绑定成功"
  rescue EmailVerificationService::Error => e
    redirect_to users_profile_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to users_profile_path, alert: "设置失败：#{e.message}"
  end
end
