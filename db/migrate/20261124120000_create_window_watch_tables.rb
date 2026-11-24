class CreateWindowWatchTables < ActiveRecord::Migration[7.1]
  def change
    # 开窗页面月批快照头（契约 02 §二/§四）：一行 = 一个判定月，month 唯一支撑幂等覆盖
    create_table :window_watch_snapshots do |t|
      t.string :month, null: false, comment: "判定月 YYYY-MM（幂等键，同月重推=整包覆盖）"
      t.string :snapshot_version, null: false, comment: "契约版本（结构变更必须升版）"
      t.string :caliber_version, null: false, comment: "01_口径映射表版本"
      t.string :script_version, null: false, comment: "月批脚本版本"
      t.datetime :generated_at, comment: "DSH 生成时刻（含时区）"
      t.jsonb :data_snapshot, null: false, default: "{}", comment: "底座信息整块（trade_date/adjust/is_stale/stale_days 等，页面直接读）"
      t.jsonb :universe, null: false, default: "{}", comment: "全市场计数（market/count/exchanges）"
      t.jsonb :stats, null: false, default: "{}", comment: "统计（tier_counts/main_group_run3/run5/finance/st/bj，全字段非空）"
      t.text :disclaimer, null: false, comment: "免责声明原文（页脚逐字渲染，不得改写）"

      t.timestamps
    end
    add_index :window_watch_snapshots, :month, unique: true

    # 逐股行表（契约 §三）：≈927 行/月，支撑全量视图 SQL 筛选/排序/分页与历史月保留
    # 判定字段全部来自 DSH 月批，页面只消费不计算；hist 等 6 位小数对齐契约 Q3
    create_table :window_watch_snapshot_stocks do |t|
      t.references :window_watch_snapshot, null: false, foreign_key: true, comment: "所属快照"
      t.string :symbol, null: false, comment: "600519.SH 格式"
      t.string :code, null: false, comment: "sh600519 底座码"
      t.string :name, null: false, comment: "股票简称（含 ST 前缀）"
      t.string :industry, null: false, default: "", comment: "行业（质量矩阵口径，允许空串）"
      t.string :exchange, null: false, comment: "SH/SZ（tiers 内无 BJ）"
      t.string :tier, null: false, comment: "T1/T2_P2/T2_P1/T3"
      t.string :subtag, null: false, default: "", comment: "continuation/sticky_micro/high_gate/no_low_premise/空"
      t.boolean :finance, null: false, default: false, comment: "金融四行业"
      t.boolean :st, null: false, default: false, comment: "ST/*ST（仅标注不剔除）"
      t.boolean :run3_asof, comment: "决策时点连续3年 ROE≥15 且经营现金流>0（null=无财报）"
      t.boolean :run5_asof, comment: "连续5年口径"
      t.decimal :roe, precision: 6, scale: 2, comment: "as-of 年报加权 ROE（%），null=无财报"
      t.string :roe_band, null: false, default: "", comment: "ROE 档位文案"
      t.decimal :hist, precision: 14, scale: 6, null: false, comment: "判定月 MACD 柱（前复权，6位小数；页面不渲染数值）"
      t.decimal :prev_hist, precision: 14, scale: 6, null: false, comment: "上月 MACD 柱"
      t.decimal :dif, precision: 14, scale: 6, null: false, comment: "判定月 DIF"
      t.decimal :dea, precision: 14, scale: 6, null: false, comment: "判定月 DEA"
      t.decimal :ratio, precision: 14, scale: 6, null: false, comment: "|hist|/|DEA| 贴0轴比值（仅排序/标注）"
      t.string :open_month, comment: "T1 专属：开窗月"
      t.integer :months_since_open, comment: "T1 专属：开窗至今月数"
      t.string :last_close_month, comment: "T2_P2 续命用：前窗关闭月"
      t.integer :sa_run, null: false, comment: "状态A连续成立月数（P1 档=中断前连续月数）"

      t.timestamps
    end
    add_index :window_watch_snapshot_stocks, %i[window_watch_snapshot_id symbol], unique: true, name: "idx_wwss_snapshot_symbol"
    add_index :window_watch_snapshot_stocks, %i[window_watch_snapshot_id tier], name: "idx_wwss_snapshot_tier"
    add_index :window_watch_snapshot_stocks, %i[window_watch_snapshot_id tier run3_asof], name: "idx_wwss_snapshot_tier_run3"
    add_index :window_watch_snapshot_stocks, %i[window_watch_snapshot_id industry], name: "idx_wwss_snapshot_industry"

    # ingest 审计日志（契约 §四 审计行）：成功与拒绝都落，供追溯
    create_table :window_watch_ingest_logs do |t|
      t.string :snapshot_month, comment: "快照 month（解析不出时为 null）"
      t.string :snapshot_version, comment: "快照契约版本"
      t.jsonb :counts, comment: "落库计数（成功时）"
      t.string :source_ip, comment: "来源 IP"
      t.string :result, null: false, comment: "ok/rejected"
      t.text :error_messages, comment: "拒绝原因逐条（rejected 时；列名避开 AR errors 方法）"

      t.timestamps
    end
    add_index :window_watch_ingest_logs, :created_at
  end
end
