# 企业质量档案接口：financial_indicators 补扣非/披露日期/真实稀释EPS字段
# 数据源为东财 F10 主要财务数据（RPT_F10_FINANCE_MAINFINADATA），由 CnFetcher#fetch_f10_supplement 回填
class AddDeductedFieldsToFinancialIndicators < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_indicators, :deducted_net_profit, :decimal, precision: 20, scale: 2, comment: "扣非归母净利润" unless column_exists?(:financial_indicators, :deducted_net_profit)
    add_column :financial_indicators, :deducted_roe_weighted, :decimal, precision: 20, scale: 2, comment: "扣非加权平均ROE" unless column_exists?(:financial_indicators, :deducted_roe_weighted)
    add_column :financial_indicators, :disclosed_at, :date, comment: "披露日期" unless column_exists?(:financial_indicators, :disclosed_at)
    # 注意：现有 diluted_eps 列存的是扣非基本EPS（源DEDUCT_BASIC_EPS，历史命名错位），真实稀释EPS单独存本列
    add_column :financial_indicators, :eps_diluted, :decimal, precision: 20, scale: 2, comment: "稀释每股收益（源EPSXS）" unless column_exists?(:financial_indicators, :eps_diluted)
  end
end
