# 登录态下用「绑定邮箱验证码」设置/修改登录密码（免当前密码）：
# 登录态 + 邮箱验证码 = 所有权证明，与绑定邮箱流程同口径。
# 统一走验证码而非当前密码，覆盖 Google/微信建号从未自设密码的死角
# （初始密码是用户不可知的随机 token，要求当前密码即死路）。
# 错误提示走 flash[:password_error]，由个人中心「登录密码」卡片就地渲染。
class Users::PasswordSettingsController < ApplicationController
  before_action :authenticate_user!

  def create
    if current_user.email_placeholder?
      redirect_to users_profile_path, flash: { password_error: "请先绑定真实邮箱，再设置登录密码" } and return
    end

    EmailVerificationService.issue(email: current_user.email, purpose: "set_password", ip: request.remote_ip)
    redirect_to users_profile_path, notice: "验证码已发送至 #{current_user.email}，10 分钟内有效"
  rescue EmailVerificationService::Error => e
    redirect_to users_profile_path, flash: { password_error: e.message }
  rescue Net::SMTPError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
    Rails.logger.error "[PasswordSetting] 验证码邮件投递失败: #{e.class}: #{e.message}"
    redirect_to users_profile_path, flash: { password_error: "邮件服务暂时不可用，请稍后再试" }
  end

  def update
    if params[:password].blank? || params[:password_confirmation].blank?
      redirect_to users_profile_path, flash: { password_error: "请填写新密码与确认密码（至少 8 位）" } and return
    end
    if params[:password] != params[:password_confirmation]
      redirect_to users_profile_path, flash: { password_error: "两次输入的密码不一致，请重新提交" } and return
    end

    EmailVerificationService.verify!(email: current_user.email, purpose: "set_password", code: params[:code])

    current_user.update!(password: params[:password], password_confirmation: params[:password_confirmation])
    bypass_sign_in(current_user)
    redirect_to users_profile_path, notice: "登录密码已更新"
  rescue EmailVerificationService::Error => e
    redirect_to users_profile_path, flash: { password_error: e.message }
  rescue ActiveRecord::RecordInvalid => e
    # zh-CN 缺字段级校验翻译，禁止把 e.message 透出到界面
    Rails.logger.warn "[PasswordSetting] 提交失败 user=#{current_user.id}: #{e.message}"
    redirect_to users_profile_path, flash: { password_error: "设置失败：请确认新密码不少于 8 位且两次输入一致" }
  end
end
