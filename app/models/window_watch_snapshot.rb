# 开窗页面月批快照头（契约 02 v0.3 §二/§四）
# 页面永远渲染 latest（month 最大的一条成功落库快照）；历史月保留可回看（V1 不做入口）
class WindowWatchSnapshot < ApplicationRecord
  has_many :stocks, class_name: "WindowWatchSnapshotStock",
                    foreign_key: :window_watch_snapshot_id,
                    dependent: :delete_all

  scope :recent_first, -> { order(month: :desc) }

  def self.latest
    recent_first.first
  end

  # data_snapshot 便捷读取（is_stale 警示、数据截至横幅用）
  def trade_date  = data_snapshot["trade_date"]
  def is_stale?   = data_snapshot["is_stale"] == true
end
