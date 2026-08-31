module ApplicationHelper
  SITE_NAME = "HOLDLE"

  # 品牌 logo（JSON-LD Organization / Article 的 publisher.logo 用）。
  # 2026-08-31 由 PIL 程序化生成（public/holdle-logo.png，深蓝+金，上升柱+字标）；
  # 若后续有更好的品牌 logo 图，放 public/ 下替换此处即可。
  BRAND_LOGO_URL = "https://www.holdle.com/holdle-logo.png"

  # ── SEO 辅助方法 ──────────────────────────────────
  # 在视图中调用以设置页面级元数据，例如：
  #   <% set_page_title "自定义标题" %>
  #   <% set_page_description "页面描述，约 150 字" %>
  #   <% set_page_keywords "关键词1, 关键词2" %>
  # ──────────────────────────────────────────────────

  def set_page_title(title)
    content_for(:page_title, title)
  end

  def set_page_description(desc)
    content_for(:page_description, desc)
  end

  def set_page_keywords(kw)
    content_for(:page_keywords, kw)
  end

  # 渲染静态 Markdown 内容（关于页等），渲染后做白名单 sanitize 防 XSS
  def markdown_render(source)
    sanitize MarkdownRenderer.render(source), tags: %w[p a img ul ol li h1 h2 h3 h4 h5 h6 pre code blockquote table thead tbody tr th td strong em br hr span div], attributes: %w[href src alt class id target rel width height]
  end

  # 便捷方法：一键设置股票详情页的 SEO 元数据
  def set_stock_seo(stock)
    name    = stock.name.presence || stock.symbol
    market  = market_label(stock.market)
    sector  = stock.sector.presence
    desc    = "查看#{name}(#{stock.symbol})的完整财务数据、#{sector}行业对比、金字塔评分及智能投资分析。#{market}股票实时数据。"
    set_page_title "#{name}(#{stock.symbol}) - #{market}"
    set_page_description desc
    set_page_keywords "#{stock.symbol},#{name},#{market},#{sector},股票分析,财务数据,金字塔评分"
  end

  # 页面 title：统一模板「{页面主题} | HOLDLE」（品牌名固定在末尾）。
  # 首页保留完整品牌化 title，不追加后缀，避免 HOLDLE 重复。
  def page_title(default_title = "概率交易系统与长期投资学习社区")
    t = content_for(:page_title)
    return t if t.present? && home_page?
    t.present? ? "#{t} | #{SITE_NAME}" : "#{SITE_NAME} | #{default_title}"
  end

  # 是否首页（首页 index 不套「 | HOLDLE」后缀）
  def home_page?
    controller_name == "home" && action_name == "index"
  end

  def page_description(default_desc = nil)
    d = content_for(:page_description)
    d.presence || default_desc || "HOLDLE 提供港股、美股、A股财务数据深度分析，金字塔评分系统、行业对比与智能选股工具，助力投资者做出更明智的决策。"
  end

  def page_keywords(default_kw = nil)
    k = content_for(:page_keywords)
    k.presence || default_kw || "股票分析,港股,美股,A股,财务数据,金字塔评分,智能选股,行业对比,投资分析"
  end

  # OG 类型：默认 website；文章页等需单独类型时用 set_og_type 覆盖
  def set_og_type(type)
    content_for(:og_type, type)
  end

  def page_og_type
    content_for(:og_type).presence || "website"
  end

  # ── JSON-LD 结构化数据 ──────────────────────────────────
  # 页面调用 add_json_ld(hash) 追加自己的结构化数据；layout 头部统一渲染。
  # 全站 Organization 由 layout 直接渲染，见 organization_json_ld。
  def add_json_ld(data)
    content_for(:page_json_ld, json_ld_script(data))
  end

  def json_ld_script(data)
    raw %(<script type="application/ld+json">#{json_escape(data.to_json)}</script>)
  end

  # 全站 Organization（品牌 + 社交媒体链接，来自 footer 真实地址）
  def organization_json_ld
    {
      "@context": "https://schema.org",
      "@type": "Organization",
      "name": "HOLDLE",
      "url": "https://www.holdle.com/",
      "logo": BRAND_LOGO_URL,
      "description": "HOLDLE 投研助手——把 17 年投资方法论装进你的 AI",
      "sameAs": [
        "https://www.youtube.com/@EmileSu",
        "https://space.bilibili.com/270587047"
      ]
    }
  end

  # 首页 FAQ 数据（单一数据源）。⚠️ 修改首页 FAQ 区块文案时，请同步更新此常量，
  # 保证 FAQPage JSON-LD 与页面展示保持一致（见 home/index.html.erb 的 FAQ 区块）。
  HOME_FAQ_DATA = [
    ["适合什么人学习？", "对未来有更高追求，希望凭自己的智慧独立去做投资交易的人。萌新手能少走 5 年弯路；多年老手可对比是否殊途同归；所有人都能成为更好的自己。"],
    ["会不会很难？", "比想象的简单得多。交易无非解决三个问题：买卖什么、什么时候买卖、什么价格买卖。会尽量少用金融术语，用文字加视频让学习轻松易懂。"],
    ["能学到什么？", "用简单高效的财务分析方法找出具备长期上涨潜力的股票、如何等待最佳交易时机、买卖环节的优化处理、高效率分散投资的方法、避免交易中的各种陷阱，方法也适用于区块链货币交易。"],
    ["有荐股群吗？", "HOLDLE 有会员微信社区交流群，便于讨论学习和分享方法心得。但没有荐股群，不会开任何每日荐股、牛股推荐群，目的是授人以渔，让你学会一套长期经过实践检验的交易方法。"],
    ["跟其他投资课程有什么不同？", "不推荐股票、不搞短线交易、不承诺收益。目标是帮你建立一套可以自己用的投资体系，从分析企业到判断价格到管理风险，每一步走明白。"],
    ["课程怎么收费？有免费内容先看吗？", "当前基础课程已开源免费，还有大量内容供了解 HOLDLE 方法论，包括视频、文章和一些在线工具。AI 助手能帮你快速理解并上手。"],
    ["HOLDLE AI 投研助手是什么？", "基于 HOLDLE 方法论知识库的智能问答服务，接入常用 AI 工具即可提问，它按 HOLDLE 完整方法论回答。是陪练助手，不是荐股工具，不推荐买卖、不预测涨跌。"],
    ["AI 助手和课程是什么关系？", "课程是系统学习 HOLDLE 方法论的完整体系，必须先学习理解；AI 助手是随行教练。先学课程打基础，AI 助手陪你实践。"],
    ["AI 助手会荐股吗？", "不会。HOLDLE 是投资学习社区，分享方法，红线是不荐股、不预测、不承诺收益。它是学习助手、实战陪练，教你判断，不替你做决定。"],
    ["AI 助手会记录我的问题吗？", "会记录提问内容，仅用于改进 HOLDLE 知识库和回答质量，内部使用不对外公开。详情见隐私政策。"]
  ].freeze

  # 首页 FAQPage（数据源为上方 HOME_FAQ_DATA 单一常量）
  def home_faq_json_ld
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "mainEntity": HOME_FAQ_DATA.map do |q, a|
        { "@type": "Question", "name": q, "acceptedAnswer": { "@type": "Answer", "text": a } }
      end
    }
  end

  # 股票详情页面包屑（当前无市场列表页路由，故仅 首页 > 股票名(代码)）
  def stock_breadcrumb_json_ld(stock)
    name = stock.name.presence || stock.symbol
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      "itemListElement": [
        { "@type": "ListItem", "position": 1, "name": "首页", "item": "https://www.holdle.com/" },
        { "@type": "ListItem", "position": 2, "name": "#{name}(#{stock.symbol})" }
      ]
    }
  end

  # /pyramid 面包屑
  def pyramid_breadcrumb_json_ld
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      "itemListElement": [
        { "@type": "ListItem", "position": 1, "name": "首页", "item": "https://www.holdle.com/" },
        { "@type": "ListItem", "position": 2, "name": "金字塔评分 - 股票智能排行" }
      ]
    }
  end

  # 文章详情 Article schema（仅公开文章由视图注入；.compact 丢弃 nil 时间字段）
  def article_json_ld(article)
    {
      "@context": "https://schema.org",
      "@type": "Article",
      "headline": article.title,
      "datePublished": (article.published_at || article.created_at)&.iso8601,
      "dateModified": article.updated_at&.iso8601,
      "author": { "@type": "Organization", "name": "HOLDLE" },
      "publisher": {
        "@type": "Organization",
        "name": "HOLDLE",
        "logo": { "@type": "ImageObject", "url": BRAND_LOGO_URL }
      },
      "mainEntityOfPage": "https://www.holdle.com/articles/#{article.id}"
    }.compact
  end

  # 市场代码转中文
  def market_label(market)
    case market
    when "US" then "美股"
    when "HK" then "港股"
    when "CN" then "A股"
    else market
    end
  end

  # 市场主题色徽章类（A股绿 / 港股琥珀 / 美股蓝）
  # 用于金字塔警示标签、详情页市场徽章、行业/板块徽章等，全站统一
  def market_badge_class(market)
    case market
    when "CN" then "bg-green-100 text-green-800"
    when "HK" then "bg-amber-100 text-amber-800"
    else "bg-blue-100 text-blue-800"
    end
  end

  # ── 设备检测 ─────────────────────────────────────

  def mobile_device?
    request.user_agent =~ /Mobile|webOS|iPhone|iPad|Android|BlackBerry|Windows Phone|Opera Mini|IEMobile/i
  end

  def wechat_browser?
    request.user_agent.to_s.include?("MicroMessenger")
  end

  # ── 原有方法 ─────────────────────────────────────

  def human_role(role)
    case role
    when "super_admin" then "超级管理员"
    when "admin" then "管理员"
    when "member" then "会员"
    when "user" then "访客"
    else role.humanize
    end
  end

  def user_avatar_tag(user, css_class: "", size: nil)
    size_css = size || "w-10 h-10"

    if user.avatar.present?
      tag.img(
        src: user.avatar,
        alt: user.nickname.presence || "avatar",
        class: "#{size_css} rounded object-cover shrink-0 #{css_class}",
        onerror: "this.onerror=null;this.style.display='none';this.nextElementSibling.style.display='flex'"
      ) + tag.div(
        user.avatar_char,
        class: "#{size_css} rounded bg-link flex items-center justify-center text-white font-bold shrink-0 #{css_class}",
        style: "display:none"
      )
    else
      tag.div(
        user.avatar_char,
        class: "#{size_css} rounded bg-link flex items-center justify-center text-white font-bold shrink-0 #{css_class}"
      )
    end
  end
end
