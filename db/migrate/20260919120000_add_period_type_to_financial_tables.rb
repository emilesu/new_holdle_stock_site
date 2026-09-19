# 财务列表改造：新增 period_type 区分年报与季报（累计口径）
# annual=12个月累计 / q3=9个月 / h1=6个月 / q1=3个月
class AddPeriodTypeToFinancialTables < ActiveRecord::Migration[7.1]
  TABLES = %i[financial_reports income_statements balance_sheets cash_flows financial_indicators].freeze

  def change
    TABLES.each do |table|
      # 历史数据全部为年报，默认值 annual 即可，无需回填脚本
      add_column table, :period_type, :string, default: "annual", null: false,
                   comment: "期次类型（annual/q1/h1/q3，累计口径）"
      add_index table, [ :stock_id, :period_type, :report_date ],
                name: "idx_#{table}_stock_period_date"
    end
  end
end
