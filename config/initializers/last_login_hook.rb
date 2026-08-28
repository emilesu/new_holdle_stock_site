# 仅在登录时更新，排除从 session 恢复（:fetch）
# :authentication = 密码登录, :set_user = Devise sign_in（含 OAuth）
Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
  if user.is_a?(User)
    user.update_column(:last_login_at, Time.current)
  end
end