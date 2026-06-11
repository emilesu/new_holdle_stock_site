class CreateBalanceSheets < ActiveRecord::Migration[7.1]
  def change
    create_table :balance_sheets do |t|
      t.belongs_to :financial_report, null: false, foreign_key: true
      t.decimal :total_assets
      t.decimal :current_assets
      t.decimal :non_current_assets
      t.decimal :total_liabilities
      t.decimal :current_liabilities
      t.decimal :non_current_liabilities
      t.decimal :total_equity

      t.timestamps
    end
  end
end
