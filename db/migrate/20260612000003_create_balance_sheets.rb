class CreateBalanceSheets < ActiveRecord::Migration[7.1]
  def change
    create_table :balance_sheets do |t|
      t.bigint :financial_report_id, null: false, comment: '关联财务报告主表ID'
      t.bigint :stock_id, null: false, comment: '股票ID，关联stocks表'
      t.date :report_date, null: false, comment: '财报日期'
      t.string :market, default: "US", null: false, comment: '市场类型（US/A股等）'
      t.string :report_type, comment: '报告类型（年度/季度）'
      t.string :currency, comment: '货币类型'
      
      t.decimal :total_assets, precision: 15, scale: 2, comment: '总资产'
      t.decimal :total_liabilities, precision: 15, scale: 2, comment: '总负债'
      t.decimal :total_equity, precision: 15, scale: 2, comment: '股东权益合计'
      t.decimal :current_assets, precision: 15, scale: 2, comment: '流动资产'
      t.decimal :current_liabilities, precision: 15, scale: 2, comment: '流动负债'
      t.decimal :cash_and_cash_equivalents, precision: 15, scale: 2, comment: '现金及现金等价物'
      t.decimal :accounts_receivable, precision: 15, scale: 2, comment: '应收账款'
      t.decimal :inventory, precision: 15, scale: 2, comment: '存货'
      t.decimal :property_plant_equipment, precision: 15, scale: 2, comment: '固定资产'
      t.decimal :long_term_debt, precision: 15, scale: 2, comment: '长期负债'
      t.decimal :short_term_debt, precision: 15, scale: 2, comment: '短期负债'
      t.decimal :retained_earnings, precision: 15, scale: 2, comment: '留存收益'
      t.decimal :intangible_assets, precision: 15, scale: 2, comment: '无形资产'
      t.decimal :goodwill, precision: 15, scale: 2, comment: '商誉'
      t.decimal :investments, precision: 15, scale: 2, comment: '投资'
      t.decimal :other_current_assets, precision: 15, scale: 2, comment: '其他流动资产'
      t.decimal :other_non_current_assets, precision: 15, scale: 2, comment: '其他非流动资产'
      t.decimal :other_current_liabilities, precision: 15, scale: 2, comment: '其他流动负债'
      t.decimal :other_non_current_liabilities, precision: 15, scale: 2, comment: '其他非流动负债'
      t.decimal :common_stock, precision: 15, scale: 2, comment: '普通股'
      t.decimal :additional_paid_in_capital, precision: 15, scale: 2, comment: '资本公积'
      t.decimal :treasury_stock, precision: 15, scale: 2, comment: '库存股'
      t.decimal :non_controlling_interest, precision: 15, scale: 2, comment: '非控制权益'

      t.timestamps
    end

    add_index :balance_sheets, :financial_report_id
    add_index :balance_sheets, :stock_id
    add_index :balance_sheets, [:stock_id, :report_date, :market], unique: true
    add_foreign_key :balance_sheets, :financial_reports
    add_foreign_key :balance_sheets, :stocks
  end
end