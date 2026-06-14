class AddUserBusinessFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :role, :string, default: "user", null: false unless column_exists?(:users, :role)
    add_column :users, :nickname, :string unless column_exists?(:users, :nickname)
    add_column :users, :member_level, :integer, default: 0, null: false unless column_exists?(:users, :member_level)
    add_column :users, :member_expire_at, :datetime unless column_exists?(:users, :member_expire_at)
    add_column :users, :bio, :text unless column_exists?(:users, :bio)
  end
end