class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    # 清除浏览器 HSTS 缓存（具体策略见 config/initializers/clear_hsts.rb）
    # 生产环境 Nginx 处理 SSL 终结，内部 Puma 始终使用 HTTP

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end
end
