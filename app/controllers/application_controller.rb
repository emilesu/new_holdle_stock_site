class ApplicationController < ActionController::Base
    # app/controllers/application_controller.rb
    include Pundit::Authorization
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    # 如果浏览器误用 HTTPS 访问，重定向回 HTTP
    before_action :redirect_https_to_http, if: -> { request.ssl? }

    # 清除浏览器 HSTS 缓存，避免后续自动跳 HTTPS
    after_action :clear_hsts

    private

    def redirect_https_to_http
      response.headers['Strict-Transport-Security'] = 'max-age=0'
      redirect_to request.original_url.gsub(/^https:/, 'http:'), allow_other_host: false
    end

    def clear_hsts
      response.headers['Strict-Transport-Security'] = 'max-age=0'
    end

    def user_not_authorized
        flash[:alert] = "您暂无权限访问该页面"
        redirect_to request.referer || root_path
    end
end
