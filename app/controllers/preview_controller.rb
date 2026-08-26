# 暗发布预览控制器：新设计页面仅站长（admin）可见，其余访问一律 404。
# 设计确认后：正式路由指向新视图，删除本控制器与 preview 路由。
class PreviewController < ApplicationController
  before_action :require_admin

  def home; end

  def join; end

  def plans; end

  private

  def require_admin
    # 404 而非重定向：不暴露预览路径的存在
    head :not_found unless current_user&.is_admin?
  end
end
