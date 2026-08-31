# sitemap 相关 XML（sitemap index / 静态页 / 股票分片）。
# 域名写死生产域名，确保 CDN 后输出一致。
# 所有分片经 Rails.cache 缓存原始 XML，避免每次请求实时全量拼 SQL。
class SitemapsController < ApplicationController
  HOST = "https://www.holdle.com".freeze
  CACHE_EXPIRES_IN = 12.hours
  SHARD_SIZE = 5000

  # 静态分片 URL（不含登录/后台页）；priority 按页面重要性配置
  STATIC_PAGES = [
    { path: "/",          priority: "1.0" },
    { path: "/pyramid",   priority: "0.9" },
    { path: "/courses",   priority: "0.9" },
    { path: "/plans",     priority: "0.8" },
    { path: "/ai-assistant", priority: "0.8" },
    { path: "/join",      priority: "0.8" },
    { path: "/articles",  priority: "0.7" },
    { path: "/about",     priority: "0.6" },
    { path: "/video",     priority: "0.6" },
    { path: "/privacy",   priority: "0.4" },
    { path: "/terms",     priority: "0.4" }
  ].freeze

  # /sitemap.xml —— sitemap index，指向各分片
  def index
    body = Rails.cache.fetch(cache_key("index"), expires_in: CACHE_EXPIRES_IN) do
      lastmod = Date.current.iso8601
      urls = shard_urls
      xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
      xml << %(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
      urls.each do |loc|
        xml << "  <sitemap>\n"
        xml << "    <loc>#{loc}</loc>\n"
        xml << "    <lastmod>#{lastmod}</lastmod>\n"
        xml << "  </sitemap>\n"
      end
      xml << "</sitemapindex>\n"
      xml
    end
    render_xml(body)
  end

  # /sitemap-static.xml —— 静态公开页
  def static
    body = Rails.cache.fetch(cache_key("static"), expires_in: CACHE_EXPIRES_IN) do
      lastmod = Date.current.iso8601
      entries = STATIC_PAGES.map do |page|
        url_entry("#{HOST}#{page[:path]}", lastmod, page[:priority])
      end.join
      urlset(entries)
    end
    render_xml(body)
  end

  # /sitemap-articles.xml —— 文章/课程/课时详情页
  def articles
    body = Rails.cache.fetch(cache_key("articles"), expires_in: CACHE_EXPIRES_IN) do
      lastmod = Date.current.iso8601
      entries = +""
      # 仅列出已发布且公开的文章，避免把草稿/会员付费墙页推给搜索引擎
      article_rows = Article.published.accessible_by(nil).pluck(:id, :updated_at)
      article_rows.each do |(id, updated_at)|
        entries << url_entry("#{HOST}/articles/#{id}", updated_at&.iso8601 || lastmod, "0.7")
      end
      course_rows = Course.pluck(:id, :updated_at)
      course_rows.each do |(id, updated_at)|
        entries << url_entry("#{HOST}/courses/#{id}", updated_at&.iso8601 || lastmod, "0.7")
      end
      lesson_rows = Lesson.pluck(:id, :updated_at)
      lesson_rows.each do |(id, updated_at)|
        entries << url_entry("#{HOST}/lessons/#{id}", updated_at&.iso8601 || lastmod, "0.6")
      end
      urlset(entries)
    end
    render_xml(body)
  end

  # /sitemap-stocks-:id.xml —— 股票详情页分片，每片最多 SHARD_SIZE(5000) 条
  def stocks
    page = params[:id].to_i
    page = 1 if page < 1
    # 页码超过实际分片数即视为无效，返回 404，避免输出空 urlset 误导搜索引擎
    return head :not_found if page > (Stock.count.to_f / SHARD_SIZE).ceil
    body = Rails.cache.fetch(cache_key("stocks/#{page}"), expires_in: CACHE_EXPIRES_IN) do
      rows = Stock.order(:id)
                  .offset((page - 1) * SHARD_SIZE)
                  .limit(SHARD_SIZE)
                  .pluck(:symbol, :market, :exchange, :updated_at)
      entries = rows.map do |(symbol, market, exchange, updated_at)|
        url_entry("#{HOST}/stocks/#{stock_url_component(symbol, market, exchange)}",
                  updated_at&.iso8601, "0.6")
      end.join
      urlset(entries)
    end
    render_xml(body)
  end

  private

  # sitemap index 里声明的所有分片 loc（股票分片按当前总量计算片数）
  def shard_urls
    urls = [
      "#{HOST}/sitemap-static.xml",
      "#{HOST}/sitemap-articles.xml"
    ]
    shard_count = (Stock.count.to_f / SHARD_SIZE).ceil
    (1..shard_count).each do |i|
      urls << "#{HOST}/sitemap-stocks-#{i}.xml"
    end
    urls
  end

  # 复刻 Stock#to_param 的 URL 规则（CN 裸代码 / HK 前缀 / US 交易所-代码）
  def stock_url_component(symbol, market, exchange)
    if market == "CN"
      symbol
    elsif market == "HK"
      "HK#{symbol.sub(/\.HK\z/, '')}"
    else
      exchange_name = exchange.present? ? exchange.gsub('证券交易所', '').strip.upcase : "NASDAQ"
      "#{exchange_name}-#{symbol.tr('.', '_')}"
    end
  end

  def url_entry(loc, lastmod, priority)
    loc = CGI.escapeHTML(loc)
    %(  <url>\n    <loc>#{loc}</loc>\n    <lastmod>#{lastmod}</lastmod>\n    <priority>#{priority}</priority>\n  </url>\n)
  end

  def urlset(entries)
    %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n#{entries}</urlset>\n)
  end

  def cache_key(name)
    "sitemap/v1/#{name}"
  end

  def render_xml(body)
    render plain: body, content_type: "application/xml"
  end
end