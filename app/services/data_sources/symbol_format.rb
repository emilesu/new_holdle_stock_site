module DataSources
  # 美股 symbol → 外部数据源代码格式的统一转换。
  # 库内 symbol 可能含 . / ^（如 BRK.B、BRK/B、NLY^F），东财与 Yahoo 的代码格式要求不同；
  # 此前各服务内联各写一份 tr 规则，规则漂移导致 BRK/B 等标的查询必空，本模块为唯一出处
  module SymbolFormat
    module_function

    # 东财：特殊字符统一转下划线（BRK/B → BRK_B、NLY^F → NLY_F，实测原样查询返回空）
    def eastmoney(symbol)
      symbol.to_s.strip.tr("./^", "_")
    end

    # Yahoo：特殊字符统一转连字符并大写（BRK/B → BRK-B、NLY^F → NLY-F）
    # 注意：tr 的 to_string 必须用单字符靠末字符补齐，实测多字符 "---" 会把 ^ 错映射成 .
    def yahoo(symbol)
      symbol.to_s.strip.upcase.tr("./^", "-")
    end

    # 库内规范形态（NYSE/Yahoo 约定）：斜杠统一为点（BRK/B → BRK.B）
    # 用于入库归一化与 ingest 命中校验（契约 v0.8：snapshot.code = Yahoo 底座码 = 点形态）。
    # 注意：^ 形态（优先股/单位，如 NLY^F）不在此映射——Yahoo 对优先股用连字符（NLY-F），
    # 且 DSH 池口径（决策 A）已排除优先股/单位，点化 ^ 反而制造错误代码
    def canonical(symbol)
      symbol.to_s.strip.tr("/", ".")
    end
  end
end
