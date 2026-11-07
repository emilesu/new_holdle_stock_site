class AddLockableToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :failed_attempts, :integer, default: 0, null: false, comment: "连续登录失败次数（PR-8 :lockable，成功登录后清零）"
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
    add_index :users, :unlock_token, unique: true
  end
end
