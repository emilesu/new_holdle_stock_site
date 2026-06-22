OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:post, :get]
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:oauth_failure).call(env)
end

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :wechat,
           ENV['WECHAT_APP_ID'],
           ENV['WECHAT_APP_SECRET'],
           scope: 'snsapi_login',
           request_path: '/users/auth/wechat',
           callback_path: '/users/auth/wechat/callback'

  provider :google_oauth2,
           ENV['GOOGLE_CLIENT_ID'],
           ENV['GOOGLE_CLIENT_SECRET'],
           scope: 'email,profile', access_type: 'online',
           request_path: '/users/auth/google_oauth2',
           callback_path: '/users/auth/google_oauth2/callback'
end