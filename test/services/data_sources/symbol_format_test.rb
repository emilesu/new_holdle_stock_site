require "test_helper"

# 美股 symbol → 外部数据源代码格式的统一转换规则
class SymbolFormatTest < ActiveSupport::TestCase
  Format = DataSources::SymbolFormat

  test "eastmoney: 点/斜杠/脱字符均转下划线" do
    assert_equal "BRK_B", Format.eastmoney("BRK/B")
    assert_equal "BRK_B", Format.eastmoney("BRK.B")
    assert_equal "NLY_F", Format.eastmoney("NLY^F")
    assert_equal "AAPL", Format.eastmoney("AAPL")
    assert_equal "AAPL", Format.eastmoney(" AAPL ")
  end

  test "yahoo: 点/斜杠/脱字符均转连字符并大写" do
    assert_equal "BRK-B", Format.yahoo("BRK/B")
    assert_equal "BRK-B", Format.yahoo("BRK.B")
    assert_equal "NLY-F", Format.yahoo("NLY^F")
    assert_equal "SOFI", Format.yahoo("sofi")
  end
end
