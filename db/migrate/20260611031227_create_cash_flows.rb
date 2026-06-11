class CreateCashFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :cash_flows do |t|
      t.belongs_to :financial_report, null: false, foreign_key: true
      t.decimal :operating_cash_flow
      t.decimal :investing_cash_flow
      t.decimal :financing_cash_flow
      t.decimal :net_cash_flow

      t.timestamps
    end
  end
end
