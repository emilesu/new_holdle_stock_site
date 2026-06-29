namespace :run do
  desc "Run a Rails command in production via rails runner"
  task :rails do
    command = ENV["CMD"]
    unless command
      warn "Usage: CMD='UsStockBasicInfoJob.perform_later' bundle exec cap production run:rails"
      exit 1
    end

    on roles(:app) do
      within current_path do
        with rails_env: :production do
          execute :rails, "runner", "'#{command}'"
        end
      end
    end
  end

  desc "Trigger the UsStockBasicInfo crawler inside Puma process"
  task :us_stock_basic do
    on roles(:app) do
      within current_path do
        with rails_env: :production do
          # Write a temp script that will be executed by rails runner
          # This runs perform_now within the rails runner process
          # Use ERB escape to defer interpolation to rails runner
          script = <<~'RUBY'
            # Trigger the crawler synchronously (within this process)
            puts "[#{Time.current}] 开始执行 UsStockBasicInfoService..."
            DataSources::UsStockBasicInfoService.call
            puts "[#{Time.current}] 执行完成!"
          RUBY

          # Write script to temp file
          script_path = "/tmp/run_us_stock_basic_#{Time.now.to_i}.rb"
          upload! StringIO.new(script), script_path

          log_path = "/var/www/holdle_stock_prod/shared/log/us_stock_basic_crawl.log"
          # Execute in background via shell string (nohup)
          execute "nohup $HOME/.rbenv/bin/rbenv exec bundle exec rails runner #{script_path} >> #{log_path} 2>&1 &"

          puts "  ✅ 爬虫任务已提交后台执行"
          puts "  📋 查看日志: tail -f #{log_path}"
        end
      end
    end
  end
end