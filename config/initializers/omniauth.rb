OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:post, :get]
OmniAuth.config.on_failure = proc do |env|
  Rack::Response.new(
    ['<html><body><script>window.location.href="/users/sign_in";</script></body></html>'],
    302,
    {'Location' => '/users/sign_in', 'Content-Type' => 'text/html'}
  ).finish
end