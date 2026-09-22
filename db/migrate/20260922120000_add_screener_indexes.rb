# 股票筛选（Screener）性能支撑索引
# 筛选查询按「年报口径 + 报告日期区间」跨股票聚合，现有索引均以 stock_id 为前缀无法命中，
# 这里为两张财务表补年报部分索引（仅 period_type='annual' 行，体积小、维护开销低）
class AddScreenerIndexes < ActiveRecord::Migration[7.1]
  def up
    execute "CREATE INDEX IF NOT EXISTS idx_fi_annual_report_date ON financial_indicators (report_date) WHERE period_type = 'annual'"
    execute "CREATE INDEX IF NOT EXISTS idx_is_annual_report_date ON income_statements (report_date) WHERE period_type = 'annual'"
  end

  def down
    execute "DROP INDEX IF EXISTS idx_fi_annual_report_date"
    execute "DROP INDEX IF EXISTS idx_is_annual_report_date"
  end
end
