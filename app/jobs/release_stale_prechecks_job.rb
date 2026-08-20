# T7 计费后台：预占超时释放（设计 §2.2 定稿）
# 预占后 60 秒未 confirm/release → 自动释放（防挂起占额度）
# 由 solid_queue recurring 每 1 分钟执行一次（config/recurring.yml）
class ReleaseStalePrechecksJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 60.seconds

  def perform
    count = UsageLog.where(status: "precheck")
                    .where("created_at < ?", Time.current - STALE_AFTER)
                    .update_all(status: "released")
    Rails.logger.info "[MCP] 释放过期预占 #{count} 条" if count.positive?
  end
end
