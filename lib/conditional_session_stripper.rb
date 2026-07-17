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
        status, headers, response = @app.call(env)

        path = env["PATH_INFO"]
        has_cookie = env["HTTP_COOKIE"].to_s.include?(SESSION_KEY)

        # 登录/注册/OAuth 页面保留 Set-Cookie（需要 CSRF token）
        excluded = EXCLUDED_PATHS.any? { |p| path.start_with?(p) }

        headers["X-Debug-Stripper"] = "path=#{path} excluded=#{excluded} has_cookie=#{has_cookie}"

        unless excluded
            unless has_cookie
                # Rack 3 headers 不支持 delete，使用 reject! 
                headers.reject! { |k, _| k.downcase == "set-cookie" }
                headers["x-debug-stripped"] = "yes"
            end
        end

        [status, headers, response]
    end
end
