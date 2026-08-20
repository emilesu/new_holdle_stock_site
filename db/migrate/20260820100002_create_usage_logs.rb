class CreateUsageLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :usage_logs do |t|
      t.string :request_id, null: false, comment: "幂等键（MCP 生成）"
      t.references :api_key, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :tool_name, comment: "holdle_ask / holdle_get_rules"
      t.text :question, comment: "问题内容（可脱敏）"
      t.string :status, default: "precheck", comment: "precheck/confirmed/released"
      t.integer :consumed, default: 0, comment: "确认扣次数（=1）"
      t.string :ip, comment: "来源 IP"
      t.datetime :created_at, null: false
      t.datetime :confirmed_at, comment: "确认时间"
    end

    add_index :usage_logs, :request_id, unique: true
    add_index :usage_logs, [:api_key_id, :status]
    add_index :usage_logs, :created_at
  end
end
