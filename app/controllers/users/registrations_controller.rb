class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_permitted_parameters, only: [:create]

  # 注册成功后先进注册引导页（onboarding），而不是直接回首页
  def after_sign_up_path_for(_resource)
    onboarding_path
  end

  private

  # 注册表单含昵称字段，Devise 默认 sanitizer 只放行 email/password，需显式放行 nickname，
  # 否则注册时 nickname 被剥离导致 validates :nickname presence 失败（422）
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:nickname])
  end
end
