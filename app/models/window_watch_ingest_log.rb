# 开窗快照 ingest 审计日志（契约 §四 审计行）：成功/拒绝均落表
class WindowWatchIngestLog < ApplicationRecord
  RESULTS = %w[ok rejected].freeze
end
