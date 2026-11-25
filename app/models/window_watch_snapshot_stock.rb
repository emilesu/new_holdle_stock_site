# 开窗页面快照逐股行（契约 §三）：判定字段全部来自 DSH 月批，页面只消费不计算
class WindowWatchSnapshotStock < ApplicationRecord
  belongs_to :window_watch_snapshot

  # 观察四档（stats.tier_counts 恒为这四键，契约 v0.5 §1.3）
  TIERS = %w[T1 T2_P2 T2_P1 T3].freeze
  # 契约 v0.5（snapshot 1.2）：排除桶第五键，tiers 内可选下发，与四档互斥
  IN_POSITION = "IN_POSITION".freeze
  ALL_TIERS = (TIERS + [IN_POSITION]).freeze
  SUBTAGS = %w[continuation sticky_micro high_gate no_low_premise].freeze
end
