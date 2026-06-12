class CreateFinancialIndicators < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_indicators do |t|
      t.bigint :financial_report_id, null: false, comment: '关联财务报告主表ID'
      t.bigint :stock_id, null: false, comment: '股票ID，关联stocks表'
      t.date :report_date, null: false, comment: '财报日期'
      t.string :market, default: "US", null: false, comment: '市场类型（US/A股等）'
      t.string :report_type, comment: '报告类型（年度/季度）'

      t.decimal :basic_eps, precision: 15, scale: 2, comment: '基本每股收益'
      t.decimal :diluted_eps, precision: 15, scale: 2, comment: '稀释每股收益'
      t.decimal :nav_ps, precision: 15, scale: 2, comment: '每股净资产'
      t.decimal :ncf_from_oa_ps, precision: 15, scale: 2, comment: '每股经营现金流'
      t.decimal :capital_reserve, precision: 15, scale: 2, comment: '资本公积'
      t.decimal :roe_avg, precision: 15, scale: 2, comment: '平均净资产收益率'
      t.decimal :roe_ttm, precision: 15, scale: 2, comment: 'TTM净资产收益率'
      t.decimal :net_interest_of_ta, precision: 15, scale: 2, comment: '总资产净利率'
      t.decimal :net_sales_rate, precision: 15, scale: 2, comment: '销售净利率'
      t.decimal :asset_liab_ratio, precision: 15, scale: 2, comment: '资产负债率'
      t.decimal :current_ratio, precision: 15, scale: 2, comment: '流动比率'
      t.decimal :quick_ratio, precision: 15, scale: 2, comment: '速动比率'
      t.decimal :gross_margin, precision: 15, scale: 2, comment: '毛利率'
      t.decimal :operating_margin, precision: 15, scale: 2, comment: '营业利润率'
      t.decimal :ebitda_margin, precision: 15, scale: 2, comment: 'EBITDA利润率'
      t.decimal :pe_ratio, precision: 15, scale: 2, comment: '市盈率'
      t.decimal :pb_ratio, precision: 15, scale: 2, comment: '市净率'
      t.decimal :ps_ratio, precision: 15, scale: 2, comment: '市销率'
      t.decimal :dividend_yield, precision: 15, scale: 2, comment: '股息率'
      t.decimal :payout_ratio, precision: 15, scale: 2, comment: '派息率'

      t.timestamps
    end

    add_index :financial_indicators, :financial_report_id
    add_index :financial_indicators, :stock_id
    add_index :financial_indicators, [:stock_id, :report_date, :market], unique: true
    add_foreign_key :financial_indicators, :financial_reports
    add_foreign_key :financial_indicators, :stocks
  end
end