# 财务四表金额字段精度扩容：decimal(15,2) → decimal(20,2)
#
# 背景：decimal(15,2) 上限约 ±9.99 万亿（1e13），巨型银行（工行/建行/中行等）
# 与日元/韩元/比索本位公司（丰田/瑞穗/野村等）的总资产、总负债、期末现金等
# 绝对值已突破上限，抓取写入触发 NumericValueOutOfRange 后被溢出保护置空，
# 导致详情页派生指标缺失、金字塔 ROA 项丢分（详见后台数据质量 value_overflow 台账）。
#
# 实现要点：
#   - 只改 precision（15→20），scale 保持 2，存量值转换无损、舍入口径不变；
#   - PostgreSQL numeric 按实际位数变长存储，扩容不增加表体积与查询开销；
#   - 每张表合并为单条 ALTER 语句，一次重写完成全部列，最小化 ACCESS EXCLUSIVE 锁窗口；
#   - 四张表在同一事务内执行（Rails 迁移默认事务），要么全部成功要么全部回滚。
class ExpandFinancialDecimalPrecision < ActiveRecord::Migration[7.1]
  # 财务四张子表：income_statements / balance_sheets / cash_flows / financial_indicators
  FINANCIAL_TABLES = %w[ income_statements balance_sheets cash_flows financial_indicators ].freeze

  def up
    expand(FINANCIAL_TABLES, from: "numeric(15,2)", to: "numeric(20,2)")
  end

  def down
    # 注意：若库中已存在超过 1e13 的值，回退会失败，属预期行为
    expand(FINANCIAL_TABLES, from: "numeric(20,2)", to: "numeric(15,2)")
  end

  private

  # 按类型匹配收集列名，每表拼一条 ALTER TABLE ... ALTER COLUMN a TYPE x, ALTER COLUMN b TYPE y
  def expand(tables, from:, to:)
    tables.each do |table|
      alterations = connection.columns(table).filter_map do |col|
        next unless col.sql_type == from

        "ALTER COLUMN #{connection.quote_column_name(col.name)} TYPE #{to}"
      end
      next if alterations.empty?

      execute "ALTER TABLE #{connection.quote_table_name(table)} #{alterations.join(', ')}"
    end
  end
end
