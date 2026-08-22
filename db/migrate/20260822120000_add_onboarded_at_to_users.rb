class AddOnboardedAtToUsers < ActiveRecord::Migration[7.1]
  def up
    add_column :users, :onboarded_at, :datetime, comment: "注册引导完成时间（NULL=未完成，需先过引导页）"

    # 老用户一律视为已完成引导，避免上线后全站用户被强制跳转引导页
    execute "UPDATE users SET onboarded_at = created_at WHERE onboarded_at IS NULL"
  end

  def down
    remove_column :users, :onboarded_at
  end
end
