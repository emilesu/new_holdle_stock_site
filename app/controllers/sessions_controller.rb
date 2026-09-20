class SessionsController < Devise::SessionsController
  # 登录页入口带 return_to（导航栏「登录」等）：暂存目标页，登录成功后跳回该页
  before_action :store_return_to_location, only: [:new]

  def oauth_failure
    redirect_to new_user_session_path, alert: '第三方登录授权中断，请重新登录'
  end
end