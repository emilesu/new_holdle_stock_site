module ApplicationHelper
  SITE_NAME = "Holdle"

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

  # 便捷方法：一键设置股票详情页的 SEO 元数据
  def set_stock_seo(stock)
    name    = stock.name.presence || stock.symbol
    market  = market_label(stock.market)
    sector  = stock.sector.presence
    desc    = "查看#{name}(#{stock.symbol})的完整财务数据、#{sector}行业对比、金字塔评分及智能投资分析。#{market}股票实时数据。"
    set_page_title "#{name}(#{stock.symbol}) - #{market} - #{SITE_NAME}"
    set_page_description desc
    set_page_keywords "#{stock.symbol},#{name},#{market},#{sector},股票分析,财务数据,金字塔评分"
  end

  # 页面 title（带站点名称后缀）
  def page_title(default_title = "概率交易系统与长期投资学习社区")
    t = content_for(:page_title)
    t.present? ? "#{t}" : "#{SITE_NAME} - #{default_title}"
  end

  def page_description(default_desc = nil)
    d = content_for(:page_description)
    d.presence || default_desc || "Holdle 提供港股、美股、A股财务数据深度分析，金字塔评分系统、行业对比与智能选股工具，助力投资者做出更明智的决策。"
  end

  def page_keywords(default_kw = nil)
    k = content_for(:page_keywords)
    k.presence || default_kw || "股票分析,港股,美股,A股,财务数据,金字塔评分,智能选股,行业对比,投资分析"
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
