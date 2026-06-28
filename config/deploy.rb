# config valid for current version and patch releases of Capistrano
lock "~> 3.20.1"

set :application, "holdle_stock"
set :repo_url, "git@github.com:emilesu/new_holdle_stock_site.git"

# 默认不使用分支，生产强制使用Git Tag部署
set :branch, -> { fetch(:tag) }
set :deploy_to, '/var/www/holdle_stock_prod'

# rbenv、node版本
set :rbenv_ruby, '3.2.4'
set :nvm_node, '20.20.2'

# 共享目录（持久化：环境变量、日志、上传文件、puma sock）
append :linked_dirs, 'log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'vendor/bundle', 'public/system'
append :linked_files, '.env.production', 'config/database.yml'

# 保留最近5个发布版本用于回滚
set :keep_releases, 5

# 部署完成后重启puma
after 'deploy:publishing', 'deploy:restart'
namespace :deploy do
  task :restart do
    invoke 'puma:restart'
  end
end

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, "/var/www/my_app_name"

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# append :linked_files, "config/database.yml", 'config/master.key'

# Default value for linked_dirs is []
# append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system", "vendor", "storage"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure
