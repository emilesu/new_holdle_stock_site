class SessionsController < Devise::SessionsController
  def oauth_failure
    redirect_to new_user_session_path, alert: '第三方登录授权中断，请重新登录'
  end
end