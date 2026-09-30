# 爬虫轻量定时触发器
#
# 由 config/recurring.yml 按低峰时段调度，创建执行记录并投递 CrawlerJob。
#
# 关键点：
#  1. queue_as :default —— 与 CrawlerWatchdogJob 同理，投递动作本身必须不被长任务队列阻塞。
#  2. 全局互斥闸门：只要有任何任务处于 running，本次定时直接跳过。
#     这是「手动为主 + 轻量定时」策略的核心保障——用户手动触发时，定时任务自动让路，
#     两者不会并发抢数据源配额，也不会在低配服务器上叠加负载。
class CrawlerScheduleJob < ApplicationJob
  queue_as :default

  def perform(task_key:, params: {})
    task = DataSources::CrawlerRegistry.find(task_key)
    unless task
      Rails.logger.error "[CrawlerScheduleJob] 未知任务 key: #{task_key}"
      return
    end

    if CrawlerExecution.running.exists?
      Rails.logger.info "[CrawlerScheduleJob] 已有爬虫任务在执行，本次定时跳过 #{task.name}"
      return
    end

    params = (params || {}).symbolize_keys
    execution = DataSources::CrawlerExecutionStarter.call(
      task: task,
      trigger_source: "schedule",
      params: params
    )
    Rails.logger.info "[CrawlerScheduleJob] 已入队 #{task.name}（执行记录 ##{execution.id}）"
  end
end
