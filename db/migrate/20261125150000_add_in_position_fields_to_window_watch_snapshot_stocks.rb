# 契约 v0.5（snapshot 1.2）：IN_POSITION 排除桶逐股明细新增两字段（05 变更单 §一.2）
# entry_month：存活窗口入场月 YYYY-MM（仅验格式，可晚于判定月=as-of 正常形态，口径②）
# months_in_position：DSH 算好的持仓月数 int≥1，公式不进契约，页面如实展示
class AddInPositionFieldsToWindowWatchSnapshotStocks < ActiveRecord::Migration[7.1]
  def change
    add_column :window_watch_snapshot_stocks, :entry_month, :string, comment: "IN_POSITION 专属：存活窗口入场月 YYYY-MM（可晚于判定月）"
    add_column :window_watch_snapshot_stocks, :months_in_position, :integer, comment: "IN_POSITION 专属：持仓月数（DSH 计算，int≥1）"
  end
end
