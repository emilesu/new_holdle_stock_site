class CreateApiKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :api_keys do |t|
      t.string :key_hash, null: false, comment: "SHA256(key)，不存明文"
      t.string :key_prefix, null: false, comment: "前 11 位（hl_ + 前 8 位 hex），展示用"
      t.references :user, null: false, foreign_key: true
      t.string :plan_code, null: false, comment: "当前套餐"
      t.string :status, null: false, default: "active", comment: "active/disabled/revoked"
      t.integer :quota_remaining, comment: "剩余次数（member_permanent=nil 无限）"
      t.integer :quota_total, default: 0, comment: "总次数（累计充值次数）"
      t.datetime :last_used_at, comment: "最近使用"
      t.string :disabled_reason, comment: "停用原因"
      t.timestamps
    end

    add_index :api_keys, :key_hash, unique: true
    add_index :api_keys, [:user_id, :status]
  end
end
