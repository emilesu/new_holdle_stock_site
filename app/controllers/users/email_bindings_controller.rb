# PR-6 绑定/换绑真实邮箱：验证码即时生效（reconfirmable 已关闭，不走双重链接）。
# 占位邮箱账号在此流程必须同步首设登录密码——微信建号的初始密码是用户不可知的随机 token，
# 不强制设密码会导致「绑定成功但邮箱+密码登录无效」的死角（2026-11-12 生产工单）。
# 错误提示走 flash[:binding_error]，由个人中心绑定卡片就地渲染（顶部全局 flash 手机上滑不到）。
class Users::EmailBindingsController < ApplicationController
  before_action :authenticate_user!

  def create
    email = EmailVerificationService.normalize(params[:email])

    unless email.match?(Devise.email_regexp)
      redirect_to users_profile_path, flash: { binding_error: "邮箱格式不正确" } and return
    end
    if User.exists?(email: email)
      redirect_to users_profile_path, flash: { binding_error: "该邮箱已被其他账号使用，请确认后重试或联系站长" } and return
    end

    session[:binding_email] = email
    EmailVerificationService.issue(email: email, purpose: "bind_email", ip: request.remote_ip)
    redirect_to users_profile_path, notice: "验证码已发送至 #{email}，10 分钟内有效"
  rescue EmailVerificationService::Error => e
    # 不清 session[:binding_email]：限流/异常只是本次发码失败，
    # 此前已发出的验证码在 10 分钟窗口内仍然有效，清掉反而把用户锁在门外
    redirect_to users_profile_path, flash: { binding_error: e.message }
  rescue Net::SMTPError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
    # 验证码邮件为同步发送（非 Devise 通知链路），SMTP 故障时给出友好提示而非 500
    Rails.logger.error "[EmailBinding] 验证码邮件投递失败: #{e.class}: #{e.message}"
    redirect_to users_profile_path, flash: { binding_error: "邮件服务暂时不可用，请稍后再试" }
  end

  def update
    email = session[:binding_email]
    if email.blank?
      redirect_to users_profile_path, flash: { binding_error: "请先点击「获取验证码」" } and return
    end

    # 先校验表单再消耗一次性验证码，避免密码笔误导致整码作废重取
    if params[:password].blank? || params[:password_confirmation].blank?
      redirect_to users_profile_path, flash: { binding_error: "请设置登录密码（至少 8 位），绑定后需用邮箱+密码登录" } and return
    end
    if params[:password] != params[:password_confirmation]
      redirect_to users_profile_path, flash: { binding_error: "两次输入的密码不一致，请重新提交" } and return
    end

    EmailVerificationService.verify!(email: email, purpose: "bind_email", code: params[:code])

    current_user.update!(
      email: email, confirmed_at: Time.current,
      password: params[:password], password_confirmation: params[:password_confirmation]
    )
    session.delete(:binding_email)
    bypass_sign_in(current_user)
    redirect_to users_profile_path, notice: "绑定成功，现在可用 #{email} + 密码登录"
  rescue EmailVerificationService::Error => e
    redirect_to users_profile_path, flash: { binding_error: e.message }
  rescue ActiveRecord::RecordInvalid => e
    # zh-CN 缺字段级校验翻译，禁止把 e.message 透出到界面（会显示英文/Translation missing 原文）
    Rails.logger.warn "[EmailBinding] 绑定提交失败 user=#{current_user.id}: #{e.message}"
    redirect_to users_profile_path, flash: { binding_error: "设置失败：请检查邮箱未被其他账号占用、密码不少于 8 位且两次输入一致后重试" }
  end
end
