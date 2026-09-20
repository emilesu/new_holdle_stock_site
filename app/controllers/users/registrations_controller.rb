class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_permitted_parameters, only: [:create]
  # 注册页入口带 return_to：暂存目标页，注册成功后跳回该页（无来源页时仍进引导页）
  before_action :store_return_to_location, only: [:new]

  # 注册成功后：带来源页的回来源页（引导延后一次，见 ApplicationController#redirect_to_onboarding_if_needed），
  # 否则先进注册引导页（onboarding）
  def after_sign_up_path_for(_resource)
    stored_location_for(:user) || onboarding_path
  end

  private

  # 注册表单含昵称字段，Devise 默认 sanitizer 只放行 email/password，需显式放行 nickname，
  # 否则注册时 nickname 被剥离导致 validates :nickname presence 失败（422）
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:nickname])
  end
end
