# 忘记密码改造：弃用 Devise 邮件重置链接（阿里云企业邮箱的链接预取机器人会秒消费
# reset_password_token，用户点链接时已失效），统一改为「邮箱验证码」重置，
# 与绑定邮箱/登录态改密同口径。视图沿用 devise/passwords/new（控制器继承链自动命中）。
class Users::PasswordResetsController < Devise::PasswordsController
  # edit 不再展示旧邮件链接表单（统一重定向到验证码流程），跳过父类的 token 断言
  skip_before_action :assert_reset_token_passed, only: :edit

  # POST /users/password —— 凭邮箱发验证码
  def create
    self.resource = User.find_by(email: EmailVerificationService.normalize(submitted_email))
    if resource.nil?
      # 明示未注册而非静默假发码：微信/Google 用户不知道占位邮箱，最容易在这里迷路
      flash.now[:alert] = "该邮箱未注册。若您曾用微信/Google 登录，请用对应方式登录后，在个人中心绑定此邮箱"
      render :new, status: :unprocessable_content
      return
    end

    EmailVerificationService.issue(email: resource.email, purpose: "reset_password", ip: request.remote_ip)
    @email_sent = resource.email
    flash.now[:notice] = "验证码已发送至 #{resource.email}，10 分钟内有效"
    render :new, status: :unprocessable_content
  rescue EmailVerificationService::Error => e
    @email_sent = submitted_email
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_content
  rescue Net::SMTPError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
    Rails.logger.error "[PasswordReset] 验证码邮件投递失败: #{e.class}: #{e.message}"
    flash.now[:alert] = "邮件服务暂时不可用，请稍后再试"
    render :new, status: :unprocessable_content
  end

  # PATCH/PUT /users/password —— 验证码 + 新密码直接重置
  def update
    email = EmailVerificationService.normalize(submitted_email)
    self.resource = User.find_by(email: email)
    if resource.nil?
      redirect_to new_user_password_path, alert: "重置请求已过期，请重新获取验证码" and return
    end
    if params[:password].blank? || params[:password] != params[:password_confirmation]
      render_reset_error(email, "请填写新密码，并确保两次输入一致（至少 8 位）") and return
    end

    EmailVerificationService.verify!(email: email, purpose: "reset_password", code: params[:code])

    # 未确认账号经验证码重置视同完成邮箱确认（与 OAuth 建号免确认同口径）
    resource.update!(
      password: params[:password], password_confirmation: params[:password_confirmation],
      confirmed_at: resource.confirmed_at || Time.current
    )
    redirect_to new_user_session_path, notice: "密码重置成功，请用新密码登录"
  rescue EmailVerificationService::Error => e
    render_reset_error(EmailVerificationService.normalize(submitted_email), e.message)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[PasswordReset] 重置失败 email=#{submitted_email}: #{e.message}"
    render_reset_error(EmailVerificationService.normalize(submitted_email), "重置失败：请确认新密码不少于 8 位且两次输入一致")
  end

  # GET /users/password/edit —— 旧邮件链接入口已废弃，引导回验证码流程
  def edit
    redirect_to new_user_password_path, alert: "重置方式已升级为邮箱验证码，请重新发起重置"
  end

  private

  # 新表单为扁平 email 参数；兼容旧 Devise 嵌套 user[email] 形式的调用方
  def submitted_email
    params[:email].presence || params.dig(:user, :email).to_s
  end

  def render_reset_error(email, message)
    @email_sent = email
    flash.now[:alert] = message
    render :new, status: :unprocessable_content
  end
end
