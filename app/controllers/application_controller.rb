class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    # 匿名用户访问公共页面时跳过 session，使 CDN 能缓存页面
    # 解决移动网络（联通 5G）对 www.holdle.com SNI 的 DPI 拦截问题
    # 登录/注册页面保留 session（需要 CSRF token 提交表单）
    before_action :skip_session_for_anonymous_public_pages

    EXCLUDED_SESSION_PATHS = %w[
        /users/sign_in
        /users/sign_up
        /users/password
    ].freeze

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end

    private

    def skip_session_for_anonymous_public_pages
        return unless request.get?
        return if user_signed_in?
        return if EXCLUDED_SESSION_PATHS.any? { |p| request.path.start_with?(p) }

        request.session_options[:skip] = true
    end
end
