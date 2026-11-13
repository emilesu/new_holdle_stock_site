require "test_helper"

class PinyinInitialsTest < ActiveSupport::TestCase
  # 多音字修正：银行 háng、重庆 chóng、西藏 zàng、会稽 kuài、大参林 shēn、王朝 cháo
  test "多音字词表修正" do
    {
      "浦发银行" => "PFYH",
      "工商银行" => "GSYH",
      "平安银行" => "PAYH",
      "浙商银行" => "ZSYH",
      "渝农商行" => "YNSH",
      "东莞农商银行" => "DGNSYH",
      "世联行" => "SLH",
      "华致酒行" => "HZJH",
      "张家港行" => "ZJGH",
      "震坤行" => "ZKH",
      "重庆啤酒" => "CQPJ",
      "重药控股" => "CYKG",
      "西藏矿业" => "XZKY",
      "奇正藏药" => "QZZY",
      "会稽山" => "KJS",
      "大参林" => "DSL",
      "王朝酒业" => "WCJY",
      "朝阳科技" => "CYKJ",
      "腾讯控股" => "TXKG",
      "贵州茅台" => "GZMT"
    }.each do |name, expected|
      assert_equal expected, PinyinInitials.call(name), "#{name} 拼音首字母错误"
    end
  end

  # 未列入词表的"行/重/朝"保持默认读音（xíng/zhòng/zhāo）
  test "非词表多音字走默认读音" do
    {
      "三人行" => "SRX",
      "并行科技" => "BXKJ",
      "知行科技" => "ZXKJ",
      "三一重工" => "SYZG",
      "中联重科" => "ZLZK",
      "朝云集团" => "ZYJT"
    }.each do |name, expected|
      assert_equal expected, PinyinInitials.call(name), "#{name} 拼音首字母错误"
    end
  end

  # 与旧逐字逻辑一致的非汉字处理：字母/数字保留、括号丢弃
  test "非汉字字符处理" do
    assert_equal "WKA", PinyinInitials.call("万科A")
    assert_equal "YDGJKG", PinyinInitials.call("亿都（国际控股）")
    assert_equal "STCY", PinyinInitials.call("ST长园")
    assert_equal "", PinyinInitials.call(nil)
    assert_equal "", PinyinInitials.call("")
  end
end
