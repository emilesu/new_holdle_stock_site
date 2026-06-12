class CreateCashFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :cash_flows do |t|
      t.bigint :financial_report_id, null: false, comment: '关联财务报告主表ID'
      t.bigint :stock_id, null: false, comment: '股票ID，关联stocks表'
      t.date :report_date, null: false, comment: '财报日期'
      t.string :market, default: "US", null: false, comment: '市场类型（US/A股等）'
      t.string :report_type, comment: '报告类型（年度/季度）'

      t.decimal :operating_cash_flow, precision: 15, scale: 2, comment: '经营活动现金流量净额'
      t.decimal :investing_cash_flow, precision: 15, scale: 2, comment: '投资活动现金流量净额'
      t.decimal :financing_cash_flow, precision: 15, scale: 2, comment: '筹资活动现金流量净额'
      t.decimal :net_cash_change, precision: 15, scale: 2, comment: '现金及等价物净增加额'
      t.decimal :beginning_cash, precision: 15, scale: 2, comment: '期初现金及等价物'
      t.decimal :ending_cash, precision: 15, scale: 2, comment: '期末现金及等价物'

      t.timestamps
    end

    add_index :cash_flows, :financial_report_id
    add_index :cash_flows, :stock_id
    add_index :cash_flows, [:stock_id, :report_date, :market], unique: true
    add_foreign_key :cash_flows, :financial_reports
    add_foreign_key :cash_flows, :stocks
  end
end