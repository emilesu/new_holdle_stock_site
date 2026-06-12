class CreateIncomeStatements < ActiveRecord::Migration[7.1]
  def change
    create_table :income_statements do |t|
      t.bigint :financial_report_id, null: false, comment: '关联财务报告主表ID'
      t.bigint :stock_id, null: false, comment: '股票ID，关联stocks表'
      t.date :report_date, null: false, comment: '财报日期'
      t.string :market, default: "US", null: false, comment: '市场类型（US/A股等）'
      t.string :report_type, comment: '报告类型（年度/季度）'
      t.string :currency, comment: '货币类型'
      
      t.decimal :total_revenue, precision: 15, scale: 2, comment: '总营收'
      t.decimal :operating_revenue, precision: 15, scale: 2, comment: '营业收入'
      t.decimal :operating_cost, precision: 15, scale: 2, comment: '营业成本'
      t.decimal :gross_profit, precision: 15, scale: 2, comment: '毛利润'
      t.decimal :gross_margin, precision: 15, scale: 4, comment: '毛利率'
      t.decimal :operating_expense, precision: 15, scale: 2, comment: '营业费用'
      t.decimal :selling_expense, precision: 15, scale: 2, comment: '销售费用'
      t.decimal :admin_expense, precision: 15, scale: 2, comment: '管理费用'
      t.decimal :rd_expense, precision: 15, scale: 2, comment: '研发费用'
      t.decimal :operating_income, precision: 15, scale: 2, comment: '营业利润'
      t.decimal :non_operating_income, precision: 15, scale: 2, comment: '非营业收益'
      t.decimal :non_operating_expense, precision: 15, scale: 2, comment: '非营业支出'
      t.decimal :ebit, precision: 15, scale: 2, comment: '息税前利润'
      t.decimal :interest_expense, precision: 15, scale: 2, comment: '利息费用'
      t.decimal :income_before_tax, precision: 15, scale: 2, comment: '税前利润'
      t.decimal :income_tax, precision: 15, scale: 2, comment: '所得税费用'
      t.decimal :net_income, precision: 15, scale: 2, comment: '净利润'
      t.decimal :net_income_to_shareholders, precision: 15, scale: 2, comment: '归属于母公司股东净利润'
      t.decimal :basic_eps, precision: 15, scale: 4, comment: '基本每股收益'
      t.decimal :diluted_eps, precision: 15, scale: 4, comment: '稀释每股收益'
      t.decimal :weighted_avg_shares, precision: 15, scale: 2, comment: '加权平均股数'
      t.decimal :diluted_avg_shares, precision: 15, scale: 2, comment: '稀释加权平均股数'

      t.timestamps
    end

    add_index :income_statements, :financial_report_id
    add_index :income_statements, :stock_id
    add_index :income_statements, [:stock_id, :report_date, :market], unique: true
    add_foreign_key :income_statements, :financial_reports
    add_foreign_key :income_statements, :stocks
  end
end