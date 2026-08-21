# T7 Phase2：key 次数调整记录表（后台补偿/退款，可追溯）
class CreateApiKeyAdjustments < ActiveRecord::Migration[7.1]
  def change
    create_table :api_key_adjustments, comment: "API key 次数调整记录" do |t|
      t.references :api_key, null: false, foreign_key: true, comment: "被调整的 key"
      t.references :user, null: false, foreign_key: true, comment: "key 所属用户"
      t.references :admin, null: false, foreign_key: { to_table: :users }, comment: "操作管理员"
      t.integer :delta, null: false, comment: "调整次数（正=加，负=减）"
      t.string :reason, comment: "调整原因/备注"
      t.timestamps
    end
  end
end
