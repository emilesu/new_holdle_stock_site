# 开窗页面快照逐股行（契约 §三）：判定字段全部来自 DSH 月批，页面只消费不计算
class WindowWatchSnapshotStock < ApplicationRecord
  belongs_to :window_watch_snapshot

  TIERS = %w[T1 T2_P2 T2_P1 T3].freeze
  SUBTAGS = %w[continuation sticky_micro high_gate no_low_premise].freeze
end
