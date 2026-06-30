OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:post, :get]
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:oauth_failure).call(env)
end