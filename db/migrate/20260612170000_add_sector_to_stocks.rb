class AddSectorToStocks < ActiveRecord::Migration[7.1]
  def change
    add_column :stocks, :sector, :string, comment: "行业板块（中文）"
    add_index :stocks, :sector
  end
end