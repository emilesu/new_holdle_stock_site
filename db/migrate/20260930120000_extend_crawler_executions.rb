# 爬虫执行记录扩展：补齐「进度 / 心跳 / 断点 / 失败明细」
# 背景：原表只有 task_name/status/message/duration/executed_at，长任务（可跑数小时）
#       在后台只有一个笼统的 running，看不到跑到第几只；进程被部署重启或 OOM 杀掉后
#       status 永久停在 running 且无法续跑。
class ExtendCrawlerExecutions < ActiveRecord::Migration[7.1]
  def up
    add_column :crawler_executions, :task_key, :string, comment: "注册表任务 key（DataSources::CrawlerRegistry），历史记录为 NULL"
    add_column :crawler_executions, :trigger_source, :string, default: "manual", null: false, comment: "触发来源（manual/schedule/retry）"
    add_column :crawler_executions, :market, :string, comment: "涉及市场（US/HK/CN），便于筛选"
    add_column :crawler_executions, :params, :jsonb, default: {}, null: false, comment: "本次执行参数（stock_ids/after_stock_id/mode/stale_after）"
    add_column :crawler_executions, :total_count, :integer, default: 0, null: false, comment: "目标股票总数"
    add_column :crawler_executions, :processed_count, :integer, default: 0, null: false, comment: "已处理数量"
    add_column :crawler_executions, :success_count, :integer, default: 0, null: false, comment: "成功数量"
    add_column :crawler_executions, :failed_count, :integer, default: 0, null: false, comment: "失败数量"
    add_column :crawler_executions, :progress_message, :string, comment: "高频刷新的进度文案"
    add_column :crawler_executions, :checkpoint, :jsonb, default: {}, null: false, comment: "断点（如 {\"last_unit_id\": 12345}），供中断后续跑"
    add_column :crawler_executions, :error_detail, :text, comment: "异常类/消息/堆栈前 20 行"
    add_column :crawler_executions, :heartbeat_at, :datetime, comment: "心跳时间，看门狗据此判定执行进程是否已死"
    add_column :crawler_executions, :finished_at, :datetime, comment: "结束时间"

    add_index :crawler_executions, [ :task_key, :executed_at ], name: "idx_crawler_executions_task_key_executed_at"
    add_index :crawler_executions, [ :status, :heartbeat_at ], name: "idx_crawler_executions_status_heartbeat_at"

    # 状态值归一：历史 CrawlerJob 写 "error"、rake 任务写 "failed"，统一为 failed。
    # 视图与统计后续只认 running / success / failed 三态。
    execute "UPDATE crawler_executions SET status = 'failed' WHERE status = 'error'"
  end

  def down
    remove_index :crawler_executions, name: "idx_crawler_executions_status_heartbeat_at"
    remove_index :crawler_executions, name: "idx_crawler_executions_task_key_executed_at"

    remove_column :crawler_executions, :finished_at
    remove_column :crawler_executions, :heartbeat_at
    remove_column :crawler_executions, :error_detail
    remove_column :crawler_executions, :checkpoint
    remove_column :crawler_executions, :progress_message
    remove_column :crawler_executions, :failed_count
    remove_column :crawler_executions, :success_count
    remove_column :crawler_executions, :processed_count
    remove_column :crawler_executions, :total_count
    remove_column :crawler_executions, :params
    remove_column :crawler_executions, :market
    remove_column :crawler_executions, :trigger_source
    remove_column :crawler_executions, :task_key

    execute "UPDATE crawler_executions SET status = 'error' WHERE status = 'failed'"
  end
end
