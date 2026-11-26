# 美股带点码库内形态统一（2026-11-26，DSH 2026-10 重推 422 根因修复）：
# Nasdaq screener API 的分级股份用斜杠（BRK/A）入库，与 Yahoo/NYSE 惯例（BRK.A）及
# 契约 v0.8 的 snapshot.code 不一致——统一为点形态。
# 附带修复：斜杠使 to_param 产出含 / 的 URL（路由不可达，详情页本就 404），点形态经
# to_param 转下划线（NYSE-BRK_A）后详情页可达。
# 迁移前已核对（2026-11-26 psql）：13 只斜杠码与既有 61 只点形态码无碰撞对。
# ^ 形态（优先股/单位 396 只）不在范围：DSH 池已排除（决策 A），且 Yahoo 优先股用连字符。
class CanonicalizeUsSlashSymbols < ActiveRecord::Migration[7.1]
  def up
    # 碰撞预检（评审修复2）：孪生点形态行存在时裸 UPDATE 撞 idx_stocks_symbol 全局唯一索引，
    # 报错不可诊断——改为 raise 列出冲突清单，把中断变成可操作指引
    clash = select_values(<<~SQL)
      SELECT s1.symbol FROM stocks s1
      JOIN stocks s2 ON s2.symbol = replace(s1.symbol, '/', '.')
      WHERE s1.market = 'US' AND s1.symbol LIKE '%/%'
    SQL
    raise "美股斜杠码点化受阻：以下斜杠码已存在点形态孪生行，请先人工合并/清理后重跑迁移：#{clash.join(', ')}" if clash.any?

    execute "UPDATE stocks SET symbol = replace(symbol, '/', '.'), updated_at = NOW() " \
            "WHERE market = 'US' AND symbol LIKE '%/%'"
  end

  def down
    # 不可逆：点/斜杠形态无法反推原始 API 值；回滚需重跑 Nasdaq 列表爬虫
    raise ActiveRecord::IrreversibleMigration
  end
end
