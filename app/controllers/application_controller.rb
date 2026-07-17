class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    # 启用匿名用户 session 跳过，以便 CDN 缓存页面内容
    # 未登录用户的 GET 请求不发送 Set-Cookie，让 DCDN 有效缓存页面
    # 解决移动网络（联通 5G）无法访问香港服务器的问题
    after_action :skip_session_for_anonymous, if: -> { request.get? && !user_signed_in? }

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end

    private

    def skip_session_for_anonymous
        response.headers.delete('Set-Cookie')
    end
end
