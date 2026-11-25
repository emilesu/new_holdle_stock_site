class RemoveFinancialFieldsFromWindowWatchSnapshotStocks < ActiveRecord::Migration[7.1]
  # 契约 v0.4.0（老板拍板：财务指标全部移出快照，页面侧由 Trae 财务库 join）
  # 快照逐股行删除六个财务列；run3 组合索引随之删除；name/industry 保留为审计字段
  def change
    remove_index :window_watch_snapshot_stocks, name: "idx_wwss_snapshot_tier_run3"
    remove_column :window_watch_snapshot_stocks, :run3_asof, :boolean
    remove_column :window_watch_snapshot_stocks, :run5_asof, :boolean
    remove_column :window_watch_snapshot_stocks, :roe, :decimal
    remove_column :window_watch_snapshot_stocks, :roe_band, :string
    remove_column :window_watch_snapshot_stocks, :finance, :boolean
    remove_column :window_watch_snapshot_stocks, :st, :boolean
  end
end
