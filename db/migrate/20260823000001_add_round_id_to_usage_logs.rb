class AddRoundIdToUsageLogs < ActiveRecord::Migration[7.1]
  # T7 扣次粒度修复：usage_logs 加回合标识 round_id（90s 滑动窗口内合并的请求共用同一 round_id）
  def change
    add_column :usage_logs, :round_id, :string, comment: "回合标识（90s 窗口内合并的请求共用；NULL=老数据）"
    add_index :usage_logs, :round_id
    # 加速 confirm 窗口判断的 last 查询（同一 key 按 confirmed_at 倒序）
    add_index :usage_logs, [:api_key_id, :status, :confirmed_at]
  end
end
