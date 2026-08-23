# 统一 Markdown → HTML 渲染服务
# 模型（Article / Lesson）与视图 Helper 共用，避免渲染参数与后处理逻辑多处维护
class MarkdownRenderer
  class << self
    # 核心渲染：Commonmarker → 剥离高亮内联 style → 表格包 .md-table-wrap（移动端横向滚动适配）
    # 返回原始 HTML（未 sanitize），调用方需按场景自行 sanitize 或做后处理（如 Lesson 的 img 路径重写）
    def render(source)
      # Commonmarker 要求 UTF-8：nil/纯 ASCII 等输入统一标记为 UTF-8，避免编码异常
      text = source.to_s.dup.force_encoding(Encoding::UTF_8)
      html = Commonmarker.to_html(text, options: { unsafe: true, highlight: :html })
      html.gsub(/<pre\s+style="[^"]*"/, '<pre')
          .gsub(/<code\s+style="[^"]*"/, '<code')
          .gsub(/<span\s+style="[^"]*"/, '<span')
          .gsub(/<table([^>]*)>/i, '<div class="md-table-wrap"><table\1>')
          .gsub(/<\/table>/i, '</table></div>')
    end
  end
end
