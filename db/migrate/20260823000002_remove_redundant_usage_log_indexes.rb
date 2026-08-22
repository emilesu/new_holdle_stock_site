class RemoveRedundantUsageLogIndexes < ActiveRecord::Migration[7.1]
  # T7 扣次粒度修复：20260823000001 新增的复合索引 [api_key_id, status, confirmed_at]
  # 按 PostgreSQL B-tree 左前缀规则完全覆盖旧索引 [api_key_id, status] 与 [api_key_id]（t.references 自动建），删除冗余减少写放大
  def up
    remove_index :usage_logs, [:api_key_id, :status]
    remove_index :usage_logs, :api_key_id
  end

  def down
    add_index :usage_logs, [:api_key_id, :status]
    add_index :usage_logs, :api_key_id
  end
end
