class Users::IdentitiesController < ApplicationController
  before_action :authenticate_user!

  LINKABLE_PROVIDERS = %w[google_oauth2 wechat wechat_mobile].freeze

  # 发起绑定：置 session 标记后跳转第三方授权，回调在 OmniauthCallbacksController 的绑定分支处理
  def link
    provider = params[:provider].to_s
    unless LINKABLE_PROVIDERS.include?(provider)
      redirect_to users_profile_path, alert: "不支持绑定该登录方式"
      return
    end
    session[:identity_link_provider] = provider
    redirect_to omniauth_authorize_path_for(provider), allow_other_host: true
  end

  def destroy
    identity = current_user.identities.find(params[:id])
    unless current_user.can_unlink_identity?(identity)
      redirect_to users_profile_path, alert: "解绑后将没有可用的登录方式，请先绑定微信或改用真实邮箱并设置密码"
      return
    end
    identity.destroy!
    redirect_to users_profile_path, notice: "已解绑 Google 账号"
  end

  def unlink_wechat
    unless current_user.can_unlink_wechat?
      redirect_to users_profile_path, alert: "解绑后将没有可用的登录方式，请先绑定 Google 或改用真实邮箱并设置密码"
      return
    end
    current_user.update!(weixin_unionid: nil, weixin_web_openid: nil, weixin_app_openid: nil)
    redirect_to users_profile_path, notice: "已解绑微信"
  end

  private

  def omniauth_authorize_path_for(provider)
    case provider
    when "google_oauth2" then user_google_oauth2_omniauth_authorize_path
    when "wechat" then user_wechat_omniauth_authorize_path
    when "wechat_mobile" then user_wechat_mobile_omniauth_authorize_path
    end
  end
end
