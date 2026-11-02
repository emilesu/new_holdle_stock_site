# 详情页新指标「无杠杆ROE」（P1 A股）：
# 1. balance_sheets 存有息负债/归母净资产科目（源 RPT_F10_FINANCE_GBALANCE，
#    由 CnFetcher#fetch_f10_balance 回填；SHORT_LOAN/LONG_LOAN 复用已有
#    short_term_debt/long_term_debt 列，美股/港股抓取器同语义在用）
# 2. financial_indicators 存计算结果与状态 flag（口径B，由 UnleveredRoeService 重算）
class AddUnleveredRoeFields < ActiveRecord::Migration[7.1]
  def change
    add_column :balance_sheets, :parent_equity, :decimal, precision: 20, scale: 2,
               comment: "归母净资产（源TOTAL_PARENT_EQUITY）" unless column_exists?(:balance_sheets, :parent_equity)
    add_column :balance_sheets, :bond_payable, :decimal, precision: 20, scale: 2,
               comment: "应付债券（源BOND_PAYABLE）" unless column_exists?(:balance_sheets, :bond_payable)
    add_column :balance_sheets, :noncurrent_liab_1year, :decimal, precision: 20, scale: 2,
               comment: "一年内到期的非流动负债（源NONCURRENT_LIAB_1YEAR）" unless column_exists?(:balance_sheets, :noncurrent_liab_1year)
    add_column :financial_indicators, :unlevered_roe, :decimal, precision: 20, scale: 2,
               comment: "无杠杆ROE%（口径B：归母净利TTM+税后净财务费用 ÷ 归母净资产+有息负债）" unless column_exists?(:financial_indicators, :unlevered_roe)
    add_column :financial_indicators, :unlevered_roe_flag, :integer,
               comment: "无杠杆ROE状态（0正常/1未披露/2净资产≤0/3金融股；NULL=未计算）" unless column_exists?(:financial_indicators, :unlevered_roe_flag)
  end
end
