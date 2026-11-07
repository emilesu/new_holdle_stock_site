# PR-7 交叉验证归并：新注册的第三方空壳账号，用「原账号邮箱+密码」自证身份后
# 一键并入老账号（数据+凭据迁移，壳账号归档），替代旧启发式自动合并。
class Users::ClaimsController < ApplicationController
  before_action :authenticate_user!

  MAX_ATTEMPTS_PER_SESSION = 3

  def create
    unless current_user.claim_eligible?
      redirect_to root_path, alert: "当前账号不支持自助归并，如需合并账号请联系站长" and return
    end

    session[:claim_attempts] = session[:claim_attempts].to_i + 1
    if session[:claim_attempts] > MAX_ATTEMPTS_PER_SESSION
      redirect_to onboarding_path, alert: "验证失败次数过多，请联系站长人工处理" and return
    end

    email = EmailVerificationService.normalize(params[:email])
    old = User.find_by(email: email)

    # 统一失败文案，不区分「账号不存在/密码错误/已归档」，避免账号探测
    if old.nil? || old.archived? || !old.valid_password?(params[:password].to_s)
      redirect_to onboarding_path, alert: "验证失败：邮箱或密码不正确。若忘记原账号信息，请联系站长人工处理" and return
    end

    UserMergeService.new(source: current_user, target: old, note: "用户自助归并", channel: "claim").call
    old.update_column(:onboarded_at, Time.current) if old.onboarded_at.blank?
    sign_in old
    session.delete(:claim_attempts)
    redirect_to users_profile_path, notice: "归并成功：已切换到您的老账号，数据与会员权益均已合并"
  rescue UserMergeService::Error => e
    redirect_to onboarding_path, alert: "归并失败：#{e.message}"
  end
end
