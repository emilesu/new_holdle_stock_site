# 开窗页面月批快照头（契约 02 v0.3 §二/§四；v0.8 多市场：幂等键=(market, month)）
# 页面按 market 渲染各自 latest（该市场 month 最大的一条成功落库快照，不按 generated_at）；历史月保留可回看（V1 不做入口）
class WindowWatchSnapshot < ApplicationRecord
  # 契约 v0.8：market 枚举（universe.market 同域）
  MARKETS = %w[CN US].freeze

  has_many :stocks, class_name: "WindowWatchSnapshotStock",
                    foreign_key: :window_watch_snapshot_id,
                    dependent: :delete_all

  scope :recent_first, ->(market = "CN") { where(market: market).order(month: :desc) }

  def self.latest(market: "CN")
    recent_first(market).first
  end

  # data_snapshot 便捷读取（is_stale 警示、数据截至横幅用）
  def trade_date  = data_snapshot["trade_date"]
  def is_stale?   = data_snapshot["is_stale"] == true
end
