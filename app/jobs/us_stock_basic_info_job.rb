class UsStockBasicInfoJob < ApplicationJob
  queue_as :default

  def perform
    start_time = Time.current
    task_name = "爬取美股名称&行业"

    begin
      DataSources::UsStockBasicInfoService.call

      duration = (Time.current - start_time).round(2)
      CrawlerExecution.create!(
        task_name: task_name,
        status: "success",
        message: "美股名称&行业信息爬取完成",
        duration: duration,
        executed_at: start_time
      )
    rescue => e
      duration = (Time.current - start_time).round(2)
      CrawlerExecution.create!(
        task_name: task_name,
        status: "error",
        message: "执行失败: #{e.message}",
        duration: duration,
        executed_at: start_time
      )
    end
  end
end