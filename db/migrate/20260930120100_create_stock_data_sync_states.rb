# 股票数据同步状态表：每只股票 × 每种数据类型一行，作为「数据新鲜度看板」与「失败重试」的数据基础。
#
# 为什么不复用 financial_reports.last_crawled_at：
#   BaseFetcher#mark_crawled 只在「新建记录 / 数据发生变更」时调用，一次成功但无变化的抓取
#   不会更新该字段 → 直接拿来算「过期」会大面积误报；且它挂在 (stock, report_date) 粒度上，
#   按股票聚合出的「最近一次」语义不清。本表可同时记录「最近一次尝试」与「最近一次成功」。
class CreateStockDataSyncStates < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_data_sync_states, comment: "股票数据同步状态表（新鲜度看板 / 失败重试基础）" do |t|
      t.bigint :stock_id, null: false, comment: "股票ID，关联stocks表"
      t.string :market, null: false, comment: "市场类型（US/HK/CN），冗余字段便于按市场聚合"
      t.string :data_type, null: false, comment: "数据类型（profile/financial/monthly_bar/listing_date）"
      t.string :status, default: "pending", null: false, comment: "同步状态（pending/success/failed）"
      t.datetime :last_success_at, comment: "最近一次成功时间"
      t.datetime :last_attempt_at, comment: "最近一次尝试时间（含失败）"
      t.integer :retry_count, default: 0, null: false, comment: "连续失败次数，成功后归零"
      t.string :error_message, comment: "最近一次失败原因"

      t.timestamps
    end

    add_index :stock_data_sync_states, [ :stock_id, :data_type ], unique: true, name: "idx_stock_data_sync_states_stock_type"
    add_index :stock_data_sync_states, [ :market, :data_type, :last_success_at ], name: "idx_stock_data_sync_states_market_type_time"
    add_index :stock_data_sync_states, [ :data_type, :status ], name: "idx_stock_data_sync_states_type_status"
    add_foreign_key :stock_data_sync_states, :stocks
  end
end
