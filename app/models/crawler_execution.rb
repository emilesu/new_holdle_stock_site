class CrawlerExecution < ApplicationRecord
  # 状态三态：running / success / failed
  # 历史记录中的 "error" 已在迁移 20260930120000 中归一为 "failed"
  STATUSES = %w[running success failed].freeze

  # 心跳超时阈值：超过该时长未刷新心跳，即认为执行进程已死（部署重启 / OOM）
  # 取值为 CrawlContext::THROTTLE_SECONDS(5s) 的 120 倍，给「单只股票抓取耗时较长」留足余量
  WATCHDOG_TIMEOUT = 10.minutes

  # 「已置 running 但始终没有开始执行」的兜底阈值：这类记录（入队失败、作业被清理）
  # 没有心跳可判，只能用创建时间兜底。取值远大于 WATCHDOG_TIMEOUT —— crawlers 队列单线程
  # 串行，排在数小时长任务后面的记录可能长时间处于未开始状态，不能按 10 分钟误杀。
  QUEUE_TIMEOUT = 12.hours

  scope :running, -> { where(status: "running") }
  scope :by_task, ->(key) { where(task_key: key) }
  scope :for_market, ->(market) { where(market: market) }

  # 看门狗的处理对象，两类僵尸记录：
  #   1. 已开始执行但心跳停滞（heartbeat_at 超时）
  #   2. 长时间未开始执行（heartbeat_at 为 NULL 且创建时间超时）
  scope :stale, -> {
    running.where(heartbeat_at: ...WATCHDOG_TIMEOUT.ago)
           .or(running.where(heartbeat_at: nil, executed_at: ...QUEUE_TIMEOUT.ago))
  }

  # 进度百分比；目标总数未知（0）时返回 nil，由视图显示「准备中」
  def progress_percent
    return nil if total_count.to_i.zero?

    ((processed_count.to_i * 100.0) / total_count).round
  end

  def stale?
    running? && heartbeat_at.present? && heartbeat_at < WATCHDOG_TIMEOUT.ago
  end

  def running?
    status == "running"
  end

  # 是否存在可用于续跑的断点
  def resumable?
    checkpoint.present? && checkpoint["last_unit_id"].present?
  end
end
