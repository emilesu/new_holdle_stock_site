# 数据质量问题台账：月K缺口/复权因子异常、财务期次不齐/空值/溢出字段等异常的统一记录，
# 支持在后台查看与标记已处理。
#
# 唯一索引带 where resolved_at IS NULL（PostgreSQL partial unique index）：
#   保证同一个「未处理」问题不重复刷屏，同时允许同一问题在历史被处理过之后再次出现时新建记录，
#   保留完整的处理历史。
class CreateDataQualityIssues < ActiveRecord::Migration[7.1]
  def change
    create_table :data_quality_issues, comment: "数据质量问题台账" do |t|
      t.bigint :stock_id, null: false, comment: "股票ID，关联stocks表"
      t.string :market, null: false, comment: "市场类型（US/HK/CN）"
      t.string :data_type, null: false, comment: "数据类型（financial/monthly_bar）"
      t.string :issue_type, null: false, comment: "问题类型（month_gap/hfq_factor_decrease/ratio_deviation/partial_period/empty_financials/future_report_date/value_overflow）"
      t.string :severity, default: "warning", null: false, comment: "严重级别（info/warning/error）"
      t.jsonb :detail, default: {}, null: false, comment: "问题细节（区间、字段名、数值等）"
      t.datetime :detected_at, null: false, comment: "最近一次检出时间"
      t.datetime :resolved_at, comment: "处理时间（NULL=未处理）"
      t.string :resolution, comment: "处理说明（manual/ignored 等）"

      t.timestamps
    end

    add_index :data_quality_issues, [ :stock_id, :data_type, :issue_type ],
              unique: true, where: "resolved_at IS NULL",
              name: "idx_dq_issues_open_unique"
    add_index :data_quality_issues, [ :data_type, :severity ], name: "idx_dq_issues_type_severity"
    add_index :data_quality_issues, [ :market, :resolved_at ], name: "idx_dq_issues_market_resolved"
    add_foreign_key :data_quality_issues, :stocks
  end
end
