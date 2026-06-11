class CreateFinancialIndicators < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_indicators do |t|
      t.belongs_to :financial_report, null: false, foreign_key: true
      t.decimal :roe
      t.decimal :roa
      t.decimal :gross_margin
      t.decimal :net_margin
      t.decimal :debt_to_equity
      t.decimal :current_ratio
      t.decimal :quick_ratio

      t.timestamps
    end
  end
end
