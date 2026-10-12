# 统一 Markdown → HTML 渲染服务
# 模型（Article / Lesson）与视图 Helper 共用，避免渲染参数与后处理逻辑多处维护
class MarkdownRenderer
  # 档案/AI 生成内容的安全渲染白名单（对齐确认稿 §三：默认拒绝 + details/summary 放行）。
  # Rails sanitize 默认已剥离 on* 事件属性与 javascript:/data: 协议，白名单外标签整体移除。
  SAFE_TAGS = %w[p a ul ol li h1 h2 h3 h4 h5 h6 pre code blockquote
                 table thead tbody tr th td strong em br hr span div
                 details summary].freeze
  SAFE_ATTRS = %w[href src alt class id target rel width height open].freeze

  class << self
    # 核心渲染：Commonmarker → 剥离高亮内联 style → 表格包 .md-table-wrap（移动端横向滚动适配）
    # 返回原始 HTML（未 sanitize），调用方需按场景自行 sanitize 或做后处理（如 Lesson 的 img 路径重写）
    def render(source)
      # Commonmarker 要求 UTF-8：nil/纯 ASCII 等输入统一标记为 UTF-8，避免编码异常
      # 🔴 commonmarker 2.x（comrak）：unsafe 必须嵌在 render 键下，顶层写法会被静默忽略、
      # 导致 raw HTML 被替换为注释；script 等危险标签另有 GFM tagfilter 转义兜底
      text = source.to_s.dup.force_encoding(Encoding::UTF_8)
      html = Commonmarker.to_html(text, options: { render: { unsafe: true } })
      html.gsub(/<pre\s+style="[^"]*"/, '<pre')
          .gsub(/<code\s+style="[^"]*"/, '<code')
          .gsub(/<span\s+style="[^"]*"/, '<span')
          .gsub(/<table([^>]*)>/i, '<div class="md-table-wrap"><table\1>')
          .gsub(/<\/table>/i, '</table></div>')
    end

    # 安全渲染：render + 白名单 sanitize。AI 生成内容（企业质量档案）前台呈现与
    # Admin 预览必须走本方法（所见即所得），杜绝 script/iframe/on* 注入直通。
    # sanitize 产物按构造即安全，标记 html_safe 避免 ERB 输出时二次转义
    def render_safe(source)
      Rails::Html::WhiteListSanitizer.new.sanitize(render(source),
                                                   tags: SAFE_TAGS, attributes: SAFE_ATTRS).html_safe
    end
  end
end
