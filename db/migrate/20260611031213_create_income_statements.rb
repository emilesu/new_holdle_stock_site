class CreateIncomeStatements < ActiveRecord::Migration[7.1]
  def change
    create_table :income_statements do |t|
      t.belongs_to :financial_report, null: false, foreign_key: true
      t.decimal :revenue
      t.decimal :cost_of_revenue
      t.decimal :gross_profit
      t.decimal :operating_expenses
      t.decimal :operating_income
      t.decimal :net_income
      t.decimal :eps

      t.timestamps
    end
  end
end
