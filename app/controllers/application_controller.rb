class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    before_action :redirect_to_onboarding_if_needed
    before_action :set_private_cache_headers

    # 鉴权/个性化页面：禁止 CDN 公共缓存（2026-09-05 事故根因：Nginx 强制 public max-age=600
    # 导致会员小节 URL 的 302 重定向响应被 CDN 缓存，会员点击被弹走；反向也会泄露会员内容）。
    # 需与 Nginx 对这些路径透传源站 Cache-Control 配合，否则该头会被 proxy_hide_header 剥除。
    PRIVATE_CACHE_CONTROLLERS = %w[lessons courses orders pyramids stocks message_boards onboardings profiles].freeze
    PRIVATE_CACHE_ACTIONS = { "pages" => %w[join plans] }.freeze

    # 生产环境 Nginx 处理 SSL 终结，内部 Puma 始终使用 HTTP
    # HSTS（Strict-Transport-Security）统一由 CDN 层配置，Rails 不输出该头

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end

    private

    # 鉴权/个性化页面输出 private, no-store：CDN 收到后不缓存，避免会员内容/302 响应被公共缓存。
    # 注意：Nginx 必须透传该头（不能 proxy_hide_header Cache-Control 覆盖成 public），否则不生效。
    def set_private_cache_headers
        return unless private_cache_request?
        response.headers["Cache-Control"] = "private, no-store"
    end

    def private_cache_request?
        return true if controller_name.in?(PRIVATE_CACHE_CONTROLLERS)
        (PRIVATE_CACHE_ACTIONS[controller_name] || []).include?(action_name)
    end

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
