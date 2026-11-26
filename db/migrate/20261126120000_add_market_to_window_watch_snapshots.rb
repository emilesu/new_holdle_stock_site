# 契约 v0.8（美股市场化）：ingest 幂等键 month → (market, month)
# 存量快照全部回填 CN，CN 行为零变化；逐股行表无结构变更（symbol/code/exchange 字符串天然兼容 US 格式）
class AddMarketToWindowWatchSnapshots < ActiveRecord::Migration[7.1]
  def change
    add_column :window_watch_snapshots, :market, :string, null: false, default: "CN",
               comment: "市场（CN/US，契约 v0.8）：幂等键=(market, month)，同键重推=整包覆盖"
    add_column :window_watch_ingest_logs, :market, :string,
               comment: "快照市场（CN/US，契约 v0.8 审计条款；解析不出时为 null）"

    remove_index :window_watch_snapshots, name: "index_window_watch_snapshots_on_month"
    add_index :window_watch_snapshots, %i[market month], unique: true,
              name: "index_window_watch_snapshots_on_market_and_month"

    change_column_comment :window_watch_snapshot_stocks, :symbol,
                          from: "600519.SH 格式", to: "CN=600519.SH；US=<YAHOO码>.US（契约 v0.8）"
    change_column_comment :window_watch_snapshot_stocks, :code,
                          from: "sh600519 底座码", to: "CN=sh600519 底座码；US=Yahoo 底座码（落库归一小写）"
    change_column_comment :window_watch_snapshot_stocks, :exchange,
                          from: "SH/SZ（tiers 内无 BJ）", to: "CN=SH/SZ/BJ；US 恒 US（契约 v0.8）"
  end
end
