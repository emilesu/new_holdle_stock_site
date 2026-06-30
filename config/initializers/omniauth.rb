OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:post]
OmniAuth.config.on_failure = proc do |env|
  error_type = env['omniauth.error.type']
  error = env['omniauth.error']
  strategy = env['omniauth.error.strategy']
  Rails.logger.error "[OmniAuth Failure] type=#{error_type} strategy=#{strategy&.name} error=#{error&.message}"
  Rack::Response.new(
    ['<html><body><script>window.location.href="/users/sign_in";</script></body></html>'],
    302,
    {'Location' => '/users/sign_in', 'Content-Type' => 'text/html'}
  ).finish
end