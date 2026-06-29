# 本机部署，服务器用户名
server '127.0.0.1', user: 'emilesu', roles: %w{web app db}

set :rails_env, :production
set :stage, :production