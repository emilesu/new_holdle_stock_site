class AddArchivedAtToUsersAndCreateMergeLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :archived_at, :datetime, comment: "账号归并归档时间（PR-5）：非空即禁止登录，数据保留仅供审计"
    add_index :users, :archived_at

    create_table :merge_logs, comment: "账号归并审计日志（PR-5 后台 / PR-7 用户自助共用）" do |t|
      t.integer :source_user_id, null: false
      t.integer :target_user_id, null: false
      t.integer :admin_user_id
      t.string :channel, null: false, default: "admin", comment: "admin=后台人工 / claim=用户自助归并"
      t.text :payload, comment: "JSON：源账号快照与迁移计数"
      t.text :note

      t.timestamps
    end
    add_index :merge_logs, :source_user_id
    add_index :merge_logs, :target_user_id
  end
end
