Warden::Manager.after_set_user do |user, auth, opts|
  if user.is_a?(User) && opts[:event] == :authentication
    user.update_column(:last_login_at, Time.current)
  end
end