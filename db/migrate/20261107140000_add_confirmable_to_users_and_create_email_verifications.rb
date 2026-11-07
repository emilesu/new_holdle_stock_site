class AddConfirmableToUsersAndCreateEmailVerifications < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :confirmation_token, :string
    add_column :users, :confirmed_at, :datetime, comment: "邮箱验证通过时间（PR-6 :confirmable）；NULL=未验证"
    add_column :users, :confirmation_sent_at, :datetime
    add_index :users, :confirmation_token, unique: true

    # 事故级防护：存量用户必须全部标记已验证，否则上线后 9000+ 老账号全部无法登录。
    # 回填与结构变更同在一个迁移内，部署时随 db:migrate 一次性完成
    execute "UPDATE users SET confirmed_at = CURRENT_TIMESTAMP WHERE confirmed_at IS NULL"

    create_table :email_verifications, comment: "邮箱验证码（PR-6：绑定真实邮箱等场景；只存摘要不存明文）" do |t|
      t.string :email, null: false
      t.string :purpose, null: false, comment: "bind_email=绑定/换绑邮箱"
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.integer :attempt_count, null: false, default: 0
      t.string :ip

      t.timestamps
    end
    add_index :email_verifications, %i[email purpose], name: "index_email_verifications_on_email_and_purpose"
    add_index :email_verifications, :created_at
  end
end
