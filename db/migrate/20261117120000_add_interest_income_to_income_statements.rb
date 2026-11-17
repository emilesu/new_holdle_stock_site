# 美股无杠杆ROE（P2）数据源补充：
# 东财美股利润表的「利息支出」以负数呈现且为毛额，需同时采「利息收入」
# 才能还原净利息费用（与 A 股 FINANCE_EXPENSE 的净额口径对齐）。
# A股/港股不使用该列，保持 NULL。
class AddInterestIncomeToIncomeStatements < ActiveRecord::Migration[7.1]
  def change
    add_column :income_statements, :interest_income, :decimal, precision: 20, scale: 2,
               comment: "利息收入（美股口径，用于计算净利息费用）" unless column_exists?(:income_statements, :interest_income)
  end
end
