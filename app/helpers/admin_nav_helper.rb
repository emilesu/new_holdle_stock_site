# 管理后台导航：桌面端下拉分组与移动端平铺列表共用同一数据源
module AdminNavHelper
  # 业务域分组：运营 / 内容 / 数据 / AI
  def admin_nav_groups
    [
      { label: "运营", items: [
        { label: "留言管理", url: admin_message_boards_path },
        { label: "用户管理", url: admin_users_path },
        { label: "订单管理", url: admin_orders_path }
      ] },
      { label: "内容", items: [
        { label: "课程管理", url: admin_courses_path },
        { label: "文章管理", url: admin_articles_path },
        { label: "视频管理", url: admin_videos_path }
      ] },
      { label: "数据", items: [
        { label: "股票管理", url: admin_stocks_path },
        { label: "爬虫管理", url: admin_stock_crawlers_path },
        { label: "数据看板", url: admin_stock_data_path },
        { label: "数据质量", url: admin_data_quality_path }
      ] },
      { label: "AI", items: [
        { label: "AI 提问分析", url: admin_usage_analytics_path }
      ] }
    ]
  end

  # 导航项是否命中当前页：精确匹配或子路径前缀匹配（如 /admin/users/123）
  def admin_nav_active?(url)
    path = request.path
    path == url || path.start_with?("#{url}/")
  end

  # 顶级导航链接样式（深色导航栏内）
  def admin_nav_link_class(active)
    base = "px-3 py-1.5 text-hl-13 transition-colors rounded whitespace-nowrap "
    active ? "#{base}text-white bg-white/10" : "#{base}text-muted-4 hover:text-white"
  end
end
