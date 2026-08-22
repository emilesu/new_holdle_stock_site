# T7 计费后台：预占超时释放（设计 §2.2 定稿，2026-08-23 对齐扣次 90s 滑动窗口）
# 预占后 120 秒未 confirm/release → 自动释放（防挂起占额度）
# 说明：需 > 90s 合并窗口，避免 MCP 长链检索（precheck→confirm 间隔 60~90s）被提前释放
# 由 solid_queue recurring 每 1 分钟执行一次（config/recurring.yml）
class ReleaseStalePrechecksJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 120.seconds

  def perform
    count = UsageLog.where(status: "precheck")
                    .where("created_at < ?", Time.current - STALE_AFTER)
                    .update_all(status: "released")
    Rails.logger.info "[MCP] 释放过期预占 #{count} 条" if count.positive?
  end
end
