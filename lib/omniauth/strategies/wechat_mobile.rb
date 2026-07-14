require "omniauth/strategies/wechat"

module OmniAuth
  module Strategies
    class WechatMobile < OmniAuth::Strategies::Wechat
      option :name, "wechat_mobile"

      option :client_options, {
        site:          "https://api.weixin.qq.com",
        authorize_url: "https://open.weixin.qq.com/connect/oauth2/authorize?#wechat_redirect",
        token_url:     "/sns/oauth2/access_token",
        token_method:  :get
      }

      option :authorize_params, {scope: "snsapi_userinfo"}
    end
  end
end
