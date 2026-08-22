class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    before_action :redirect_to_onboarding_if_needed

    # 清除浏览器 HSTS 缓存（具体策略见 config/initializers/clear_hsts.rb）
    # 生产环境 Nginx 处理 SSL 终结，内部 Puma 始终使用 HTTP

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end

    private

    # 注册引导兜底：新注册用户（onboarded_at 为空）除引导页外，一律先进引导页
    # （Devise 控制器不继承本类，天然不受影响，无需单独排除）
    def redirect_to_onboarding_if_needed
        return unless user_signed_in?
        return if current_user.is_admin?
        return if current_user.onboarded_at.present?
        return if controller_name == "onboardings"
        redirect_to onboarding_path
    end
end
