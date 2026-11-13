# 中文股票名 → 拼音首字母（供搜索前缀匹配）
#
# chinese_pinyin gem 逐字取"第一读音"、无分词能力，多音字会被转成默认音：
# 例如"银行"→ yin xing（应为 yin hang）、"重庆"→ zhong qing（应为 chong qing）。
# 本服务先对高频多音词做最长匹配替换，其余汉字逐字回退 gem 转换，
# 非汉字字符保持与旧逻辑一致（字母/数字原样、括号等标点丢弃）。
class PinyinInitials
  # 多音词修正表：词 → 正确拼音首字母（大写）
  TERM_INITIALS = {
    # "行"读 háng（行业/商号义）；"三人行""并行科技""出行"等仍读 xíng，不在此表
    "银行" => "YH",
    "商行" => "SH",
    "酒行" => "JH",
    "表行" => "BH",
    "联行" => "LH",
    "邦行" => "BH",
    "兴行" => "XH",
    "坤行" => "KH",
    "港行" => "GH",
    # "重"读 chóng；"重工""重科""起重"等读 zhòng，走默认音
    "重庆" => "CQ",
    "重百" => "CB",
    "重药" => "CY",
    "重塑" => "CS",
    # "藏"读 zàng
    "西藏" => "XZ",
    "藏药" => "ZY",
    "藏格" => "ZG",
    # "会"读 kuài；"会展""会通"等读 huì，走默认音
    "会稽" => "KJ",
    # "参"读 shēn（大参林）
    "参林" => "SL",
    # "朝"读 cháo；"朝云"（早晨义）读 zhāo，走默认音
    "朝阳" => "CY",
    "王朝" => "WC",
    "皇朝" => "HC",
    "朝聚" => "CJ"
  }.freeze

  # 按长度降序，保证最长匹配
  TERM_KEYS = TERM_INITIALS.keys.sort_by { |t| -t.length }.freeze

  class << self
    def call(text)
      return "" if text.blank?

      chars = text.to_s
      out = +""
      i = 0

      while i < chars.length
        term = TERM_KEYS.find { |t| chars[i, t.length] == t }
        if term
          out << TERM_INITIALS[term]
          i += term.length
          next
        end

        ch = chars[i]
        if ch.match?(/\s/)
          # 与旧逻辑 split 行为一致：空白直接丢弃
        elsif ch.match?(/\p{Han}/)
          out << Pinyin.t(ch).to_s.split.first.to_s[0].to_s
        else
          # 字母/数字原样保留；括号等标点 Pinyin.t 返回空串，自然丢弃
          out << Pinyin.t(ch).to_s
        end
        i += 1
      end

      out.upcase
    end
  end
end
