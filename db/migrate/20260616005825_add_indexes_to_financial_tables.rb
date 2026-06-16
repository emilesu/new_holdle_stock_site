class AddIndexesToFinancialTables < ActiveRecord::Migration[7.1]
  def change
    add_index :financial_reports, [:stock_id, :report_date], name: 'idx_financial_reports_stock_date'
    add_index :financial_reports, [:stock_id, :status], name: 'idx_financial_reports_stock_status'
    add_index :income_statements, [:financial_report_id, :report_date], name: 'idx_income_stmts_report_date'
    add_index :balance_sheets, [:financial_report_id, :report_date], name: 'idx_balance_sheets_report_date'
    add_index :cash_flows, [:financial_report_id, :report_date], name: 'idx_cash_flows_report_date'
    add_index :financial_indicators, [:financial_report_id, :report_date], name: 'idx_fin_indicators_report_date'
    add_index :stocks, [:sector, :market], name: 'idx_stocks_sector_market'
    add_index :stocks, :symbol, name: 'idx_stocks_symbol', unique: true
  end
end