class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    before_action :redirect_to_onboarding_if_needed

    # 生产环境 Nginx 处理 SSL 终结，内部 Puma 始终使用 HTTP
    # HSTS（Strict-Transport-Security）统一由 CDN 层配置，Rails 不输出该头

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end

    private

    # 注册引导兜底：新注册用户（onboarded_at 为空）除引导页外，一律先进引导页
    # 仅拦截 GET：POST 等写操作放行，避免新用户收藏/留言等动作被 302 静默丢弃
    # （Devise 控制器不继承本类，天然不受影响，无需单独排除）
    def redirect_to_onboarding_if_needed
        return unless user_signed_in?
        return if current_user.is_admin?
        return if current_user.onboarded_at.present?
        return unless request.get?
        return if controller_name == "onboardings"
        redirect_to onboarding_path
    end
end
