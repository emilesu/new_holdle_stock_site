# 上市日期同步进度监控（solid_queue recurring 每5分钟执行一次）
# 职责：
#  - 检测到手动/nohup 启动的同步进程（rails runner 直接调用服务）时，创建或刷新"上市日期同步"的 running 记录，展示当前进度
#  - 进程退出后，把 running 记录补全为 success（含最终统计与耗时），使管理后台可见完成状态
# 说明：
#  - 经 CrawlerJob 后台队列触发的同步任务由 CrawlerJob 自身写记录，本任务仅兜底手动/命令行触发的场景
#  - 完成判定基于进程存活而非待同步数量归零：部分退市股/无 F10 数据的股票可能永远查不到上市日期
class ListingDateSyncMonitorJob < ApplicationJob
  queue_as :default

  SYNC_TASK_NAME = "上市日期同步".freeze
  # 进度信息中的监控标记：仅本监控创建/刷新过的 running 记录（message 含该标记）在进程退出时会被补全为 success，
  # 避免误标 CrawlerJob 等后台队列创建的 running 记录（如 admin 后台按钮触发）
  MONITOR_MARK = "监控每5分钟刷新".freeze

  def perform(process_alive: manual_sync_process_alive?)
    total = Stock.where(market: %w[CN HK]).count
    pending = Stock.where(market: %w[CN HK]).where(listing_date: nil).count
    record = CrawlerExecution.where(task_name: SYNC_TASK_NAME).order(executed_at: :desc).first

    if process_alive
      if record&.status == "running"
        record.update!(message: progress_message(total, pending))
      else
        CrawlerExecution.create!(
          task_name: SYNC_TASK_NAME,
          status: "running",
          message: progress_message(total, pending),
          duration: 0,
          executed_at: Time.current
        )
      end
    elsif record&.status == "running" && record.message&.include?(MONITOR_MARK)
      duration = (Time.current - record.executed_at).round(2)
      record.update!(
        status: "success",
        message: final_message(total, pending, duration),
        duration: duration
      )
    end
    # 进程退出且无 running 记录：说明没有手动任务在执行，或已有完成记录，无需处理
  end

  private

  # 检测手动/nohup 启动的上市日期同步进程（命令行含 rails runner 调用 StockListingDateService）
  def manual_sync_process_alive?
    !`pgrep -f "rails runner.*StockListingDateService"`.strip.empty?
  end

  def progress_message(total, pending)
    done = total - pending
    "同步进行中：已同步 #{done} / #{total}，待同步 #{pending} 只（#{MONITOR_MARK}）"
  end

  def final_message(total, pending, duration)
    if pending.zero?
      "上市日期同步完成：全部 #{total} 只已同步，耗时 #{duration} 秒"
    else
      "上市日期同步结束：已同步 #{total - pending} / #{total}，待同步 #{pending} 只（多为退市股或数据缺失），耗时 #{duration} 秒"
    end
  end
end
