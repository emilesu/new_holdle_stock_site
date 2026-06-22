Rails.application.config.middleware.use OmniAuth::Builder do
  # 微信网页登录 强制scope=snsapi_userinfo 必须获取UnionID
  provider :wechat,
           ENV['WECHAT_APP_ID'],
           ENV['WECHAT_APP_SECRET'],
           authorize_params: { scope: 'snsapi_userinfo' }

  # 谷歌登录（海外用户）
  provider :google_oauth2,
           ENV['GOOGLE_CLIENT_ID'],
           ENV['GOOGLE_CLIENT_SECRET'],
           scope: 'email,profile'
end

# 安全配置
OmniAuth.config.logger = Rails.logger
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:oauth_failure).call(env)
end