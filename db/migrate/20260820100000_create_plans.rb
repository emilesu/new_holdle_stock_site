class CreatePlans < ActiveRecord::Migration[7.1]
  def change
    create_table :plans do |t|
      t.string :plan_code, null: false, comment: "套餐编码（welcome/starter/light/standard/member_permanent）"
      t.string :name, null: false, comment: "展示名"
      t.integer :price_cents, default: 0, comment: "价格（分）"
      t.integer :quota, comment: "次数（nil=无限，member_permanent）"
      t.boolean :is_member_upgrade, default: false, comment: "是否升级会员（468 档=true）"
      t.boolean :active, default: true, comment: "是否在售"
      t.timestamps
    end

    add_index :plans, :plan_code, unique: true
  end
end
