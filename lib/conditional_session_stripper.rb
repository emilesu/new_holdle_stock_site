# Rack 中间件：匿名用户访问公共页面时删除 Set-Cookie 响应头
# 使 CDN 能够缓存页面内容。登录/注册页面保留 Set-Cookie（需要 CSRF token）
class ConditionalSessionStripper
    SESSION_KEY = "_stock_website_session".freeze
    EXCLUDED_PATHS = %w[
        /users/sign_in
        /users/sign_up
        /users/password
        /users/auth
    ].freeze

    def initialize(app)
        @app = app
    end

    def call(env)
        status, headers, body = @app.call(env)

        # 登录/注册/OAuth 页面保留 Set-Cookie（需要 CSRF token）
        unless EXCLUDED_PATHS.any? { |p| env["PATH_INFO"].start_with?(p) }
            # 已持有 session cookie 的用户（已登录）保留 Set-Cookie
            unless env["HTTP_COOKIE"].to_s.include?(SESSION_KEY)
                headers.delete("Set-Cookie")
            end
        end

        [status, headers, body]
    end
end
