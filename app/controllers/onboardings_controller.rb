class OnboardingsController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_already_onboarded

  def show
    @api_key = current_user.api_keys.active.first
    @preview = preview_mode?
  end

  # 完成引导：写入 onboarded_at（管理员预览模式不写），按所选目标静默跳转，不带 flash
  def complete
    current_user.update!(onboarded_at: Time.current) unless preview_mode?

    case params[:target]
    when "profile" then redirect_to users_profile_path
    when "courses" then redirect_to courses_path
    else redirect_to root_path # 含 "skip" 与非法值，一律回首页
    end
  end

  private

  # 管理员可通过 ?preview=1 预览新用户引导页（不写入引导状态，可反复查看效果）
  def preview_mode?
    current_user.is_admin? && params[:preview] == "1"
  end

  def redirect_if_already_onboarded
    return if preview_mode?
    return if current_user.onboarded_at.blank?

    redirect_to root_path
  end
end
