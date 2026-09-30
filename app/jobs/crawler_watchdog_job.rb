# 爬虫僵尸任务看门狗（solid_queue recurring 定时执行）
#
# 职责：把「心跳停滞」与「长时间未开始执行」的执行记录标记为失败，避免部署重启 /
# OOM 杀掉进程、或入队失败后，记录永久卡在 running（旧实现靠 ListingDateSyncMonitorJob
# 的 pgrep 字符串匹配兜底）。卡在 running 会通过 CrawlerScheduleJob 的全局互斥把定时爬虫一起堵死。
#
# 关键点：
#  1. 必须跑在 default 队列：crawlers 队列是单线程串行消费，长任务会把看门狗一起堵住而失效。
#  2. 保留 checkpoint 不清理：后台可据此一键「从断点续跑」。
class CrawlerWatchdogJob < ApplicationJob
  queue_as :default

  def perform
    stale_records = CrawlerExecution.stale.to_a
    return if stale_records.empty?

    now = Time.current
    stale_records.each do |record|
      started = record.heartbeat_at.present?
      record.update_columns(
        status: "failed",
        message: started ? "执行进程已中断（部署重启或 OOM），可从断点继续" :
                           "任务入队后超过 #{CrawlerExecution::QUEUE_TIMEOUT.inspect} 未开始执行，已标记失败，请重新触发",
        error_detail: started ? "心跳超过 #{CrawlerExecution::WATCHDOG_TIMEOUT.inspect} 未更新" :
                                "记录已置为执行中但始终没有心跳（入队失败或作业被清理）",
        finished_at: now,
        duration: (now - record.executed_at).round(2)
      )
    end

    Rails.logger.warn "[CrawlerWatchdogJob] 已标记 #{stale_records.size} 个僵尸任务为失败: " \
                      "#{stale_records.map(&:task_name).uniq.join(', ')}"
  end
end
