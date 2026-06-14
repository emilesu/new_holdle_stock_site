class AddLastLoginAtAndBioToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :last_login_at, :datetime unless column_exists?(:users, :last_login_at)
  end
end
