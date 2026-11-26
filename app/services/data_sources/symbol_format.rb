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
  end
end
