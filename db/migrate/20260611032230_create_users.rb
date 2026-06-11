class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email
      t.string :password_digest
      t.string :nickname
      # 加默认值 0
      t.integer :member_level, default: 0
      t.datetime :member_expire_at
      # 加默认值 "user"
      t.string :role, default: "user"

      t.timestamps
    end

    # 加 email 唯一索引
    add_index :users, :email, unique: true
  end
end
