class CreateIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :identities, comment: "第三方登录凭据（PR-3：Google 等 OAuth 凭据与账号解耦，按 provider+uid 精确归一）" do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email, comment: "绑定时的第三方邮箱快照（仅审计参考，匹配以 uid 为准）"

      t.timestamps
    end

    add_index :identities, %i[provider uid], unique: true
  end
end
