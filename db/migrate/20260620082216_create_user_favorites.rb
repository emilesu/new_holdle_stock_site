class CreateUserFavorites < ActiveRecord::Migration[7.1]
  def change
    create_table :user_favorites do |t|
      t.bigint :user_id, null: false, comment: "用户ID"
      t.bigint :stock_id, null: false, comment: "股票ID"
      t.timestamps
    end
    # 联合唯一索引：防止同一用户重复收藏同一只股票
    add_index :user_favorites, [:user_id, :stock_id], unique: true
    # 外键关联
    add_foreign_key :user_favorites, :users
    add_foreign_key :user_favorites, :stocks
  end
end
