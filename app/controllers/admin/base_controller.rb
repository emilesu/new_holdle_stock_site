module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    
    layout 'admin'

    private

    def authorize_admin!
      unless current_user&.is_admin?
        flash[:alert] = "需要管理员权限才能访问此页面"
        redirect_to new_user_session_path
      end
    end
  end
end