class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def wechat
    @user = User.find_for_wechat_oauth(request.env['omniauth.auth'])
    sign_in_and_redirect @user, event: :authentication
    set_flash_message(:notice, :success, kind: '微信') if is_navigational_format?
  end

  def google_oauth2
    @user = User.find_for_google_oauth(request.env['omniauth.auth'])
    sign_in_and_redirect @user, event: :authentication
    set_flash_message(:notice, :success, kind: 'Google') if is_navigational_format?
  end

  def failure
    redirect_to new_user_session_path, alert: '第三方登录授权失败，请重试'
  end
end