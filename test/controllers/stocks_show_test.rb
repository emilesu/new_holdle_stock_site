require "test_helper"

class StocksShowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # 构造同行业三只股票：ROE 与金字塔总分排序相反，用于验证排序依据随用户身份切换
  def setup_comparison_stocks
    sector = "饮料制造"
    @roe_high = Stock.create!(symbol: "CMP_ROE", name: "高ROE股", market: "CN", exchange: "SH",
                              sector: sector, status: "active",
                              radar_dim_scores: { "roe" => 30 }, pyramid_total_score: 600)
    @py_high = Stock.create!(symbol: "CMP_PY", name: "高金字塔股", market: "CN", exchange: "SH",
                             sector: sector, status: "active",
                             radar_dim_scores: { "roe" => 10 }, pyramid_total_score: 900)
    @base = Stock.create!(symbol: "CMP_BASE", name: "基准股", market: "CN", exchange: "SH",
                          sector: sector, status: "active",
                          radar_dim_scores: { "roe" => 20 }, pyramid_total_score: 700)
  end

  test "A股详情页展示上市日期与警示标签" do
    stock = Stock.create!(symbol: "DET_CN", name: "上市日期测试", market: "CN", exchange: "SH",
                          sector: "消费", industry: "食品", status: "active", listing_date: Date.new(2021, 5, 20))
    get stock_path(stock)
    assert_response :success
    assert_match(/上市日期/, response.body)
    assert_match(/2021-05-20/, response.body)
    # 无财务数据必然打"数据<5年"标签，验证主题色徽章实际渲染
    # 注意：ERB 自动转义 < 为 &lt;，浏览器显示仍为"数据<5年"
    # 断言限定在警示标签 span 内（title=数据不足5年提示），避免被市场/行业徽章的同名类干扰
    assert_match(/数据&lt;5年/, response.body, "详情页应展示警示标签")
    assert_match(/bg-green-100 text-green-800"\s+title="财务数据不足5年，评分可靠性较低">数据&lt;5年/,
                 response.body, "警示标签应为 A股绿色主题")
  ensure
    stock&.destroy!
  end

  # 7fa2a5c 起美股上市日期已接入展示（Yahoo firstTradeDate），原「不展示」断言为遗留坏测试，已按预期行为修正
  test "美股详情页展示上市日期行" do
    stock = Stock.create!(symbol: "DET_US", name: "US Listing Date", market: "US", exchange: "NASDAQ",
                          sector: "科技", industry: "软件", status: "active", listing_date: Date.new(2020, 3, 18))
    get stock_path(stock)
    assert_response :success
    assert_match(/上市日期/, response.body, "美股详情页应展示上市日期行")
    assert_match(/2020-03-18/, response.body)
  ensure
    stock&.destroy!
  end

  test "访客详情页对比栏按近五年ROE排序并展示警示标签" do
    setup_comparison_stocks

    get stock_path(@base)
    assert_response :success

    # 访客/非会员：保持按近五年ROE降序（30 > 20 > 10）
    assert response.body.index("高ROE股") < response.body.index("高金字塔股"),
           "访客应保持按近五年ROE排序"
    # 访客显示 ROE 数值（带%，ERB 缩进含换行/空白）
    assert_match(/>\s*30\.00%\s*</, response.body)
    # 栏目标题保持近五年ROE对比
    assert_match(/近五年ROE对比/, response.body)
    # 警示标签所有用户可见
    assert_match(/title="财务数据不足5年，评分可靠性较低">数据&lt;5年/, response.body)
  ensure
    @roe_high&.destroy! && @py_high&.destroy! && @base&.destroy!
  end

  test "会员详情页对比栏按金字塔总分排序并显示金字塔分" do
    setup_comparison_stocks
    sign_in users(:two) # admin fixture，is_member? 为 true

    get stock_path(@base)
    assert_response :success

    # 会员：按该行业金字塔总分降序（900 > 700 > 600），与 ROE 序相反
    assert response.body.index("高金字塔股") < response.body.index("高ROE股"),
           "会员应按金字塔总分排序"
    # 会员显示金字塔总分（无%，ERB 缩进含换行/空白），不再显示 ROE
    assert_match(/>\s*900\s*</, response.body)
    refute_match(/>\s*10\.00%\s*</, response.body)
    # 栏目标题切换为行业金字塔对比
    assert_match(/行业金字塔对比/, response.body)
    refute_match(/近五年ROE对比/, response.body)
  ensure
    @roe_high&.destroy! && @py_high&.destroy! && @base&.destroy!
  end

  test "会员视角对比栏已收藏股票名后显示市场主题色星标" do
    setup_comparison_stocks
    favorite = UserFavorite.create!(user: users(:two), stock: @roe_high)
    sign_in users(:two) # admin fixture，is_member? 为 true

    get stock_path(@base)
    assert_response :success
    # CN 市场主题色绿色星标；对比栏共 3 只，仅已收藏的 1 只渲染
    assert_select "span.text-green-600[title='已收藏']", count: 1, message: "已收藏的对比股票应渲染绿色主题星标"
    assert_select "span[title='已收藏']", count: 1, message: "未收藏股票不应渲染星标"
  ensure
    favorite&.destroy!
    @roe_high&.destroy! && @py_high&.destroy! && @base&.destroy!
  end

  test "访客对比栏不渲染收藏星标" do
    setup_comparison_stocks

    get stock_path(@base)
    assert_response :success
    assert_select "span[title='已收藏']", count: 0, message: "未登录不应渲染收藏星标"
  ensure
    @roe_high&.destroy! && @py_high&.destroy! && @base&.destroy!
  end

  # 企业质量档案入口：存在可读档案即对全体用户可见，且新窗口打开
  test "详情页档案入口对全体用户可见且新窗口指向最新期" do
    stock = Stock.create!(symbol: "DET_AR", name: "档案入口测试", market: "CN", exchange: "SH",
                          sector: "消费", status: "active")
    profile, = QualityProfilePublisher.call(stock: stock, period: "2025年报", title: "入口档案",
                                            markdown: "x",
                                            meta: { "gate_passed" => true, "ai_generated" => true })
    profile.publish!(users(:two))

    # 游客可见，指向最新可读期，新窗口打开
    get stock_path(stock)
    assert_response :success
    assert_includes response.body, "企业质量档案"
    assert_includes response.body, "/archive/DET_AR"
    assert_includes response.body, "2025年报"
    assert_includes response.body, 'target="_blank"'

    # 普通用户与管理员同样可见
    sign_in users(:one)
    get stock_path(stock)
    assert_includes response.body, "企业质量档案"

    sign_in users(:two)
    get stock_path(stock)
    assert_includes response.body, "企业质量档案"
  ensure
    stock&.destroy!
  end

  # 对比栏只要求有雷达数据：金字塔分低、ROE 为 0 的同行股票也要展示
  test "对比栏不再按金字塔分与ROE阈值过滤同行股票" do
    sector = "测试行业"
    low = Stock.create!(symbol: "CMP_LOW", name: "低分同行股", market: "CN", exchange: "SH",
                        sector: sector, status: "active",
                        radar_dim_scores: { "roe" => 0 }, pyramid_total_score: 100)
    base = Stock.create!(symbol: "CMP_BASE3", name: "低分基准股", market: "CN", exchange: "SH",
                         sector: sector, status: "active",
                         radar_dim_scores: { "roe" => 5 }, pyramid_total_score: 200)

    get stock_path(base)
    assert_response :success
    assert_match(/低分同行股/, response.body, "金字塔分低于 560 且 ROE 为 0 的同行股票应展示")
    assert_match(/低分基准股/, response.body, "当前股票应展示")
  ensure
    low&.destroy! && base&.destroy!
  end

  test "对比栏分页接口返回当前批次并结束分页" do
    setup_comparison_stocks

    get industry_comparison_stock_path(@base, page: 1), headers: { "Accept" => "application/json" }
    assert_response :success

    payload = JSON.parse(response.body)
    assert_includes payload["html"], "高ROE股"
    assert_includes payload["html"], "高金字塔股"
    assert_equal false, payload["has_more"]
    assert_nil payload["next_page"]
  ensure
    @roe_high&.destroy! && @py_high&.destroy! && @base&.destroy!
  end

  test "对比栏超过一批时标记还有更多并由分页接口补齐" do
    sector = "分页行业"
    stocks = 31.times.map do |i|
      Stock.create!(symbol: "PG_#{i}", name: "分页股#{i}", market: "US", exchange: "NASDAQ",
                    sector: sector, status: "active",
                    radar_dim_scores: { "roe" => 100 - i }, pyramid_total_score: 1000 - i)
    end
    base = stocks.first

    get stock_path(base)
    assert_response :success
    assert_match(/data-comparison-list-has-more-value="true"/, response.body)

    get industry_comparison_stock_path(base, page: 2), headers: { "Accept" => "application/json" }
    assert_response :success

    payload = JSON.parse(response.body)
    assert_includes payload["html"], "分页股30"
    assert_equal false, payload["has_more"]
    assert_nil payload["next_page"]
  ensure
    stocks&.each(&:destroy!)
  end

  # 构造次新股过滤场景：基准股 + 老同行 + 上市不足3年的次新同行（sector 唯一，避免服务端候选缓存串场景）
  def setup_new_listing_comparison
    sector = "次新过滤行业"
    @nl_base = Stock.create!(symbol: "NL_BASE", name: "次新基准股", market: "CN", exchange: "SH",
                             sector: sector, status: "active",
                             radar_dim_scores: { "roe" => 20 }, pyramid_total_score: 700)
    @nl_old = Stock.create!(symbol: "NL_OLD", name: "次新老同行", market: "CN", exchange: "SH",
                            sector: sector, status: "active", listing_date: Date.new(2015, 1, 1),
                            radar_dim_scores: { "roe" => 10 }, pyramid_total_score: 600)
    @nl_recent = Stock.create!(symbol: "NL_NEW", name: "次新同行股", market: "CN", exchange: "SH",
                               sector: sector, status: "active", listing_date: Date.current - 1.year,
                               radar_dim_scores: { "roe" => 30 }, pyramid_total_score: 800)
  end

  test "对比栏默认展示次新股且头部渲染过滤开关" do
    setup_new_listing_comparison

    get stock_path(@nl_base)
    assert_response :success
    assert_match(/comparison-new-listing/, response.body, "对比栏头部应渲染次新股开关")
    assert_includes response.body, "次新同行股", "默认应展示次新同行"
  ensure
    @nl_base&.destroy! && @nl_old&.destroy! && @nl_recent&.destroy!
  end

  test "对比栏 new_listing=hide 时首页与分页接口均剔除次新同行" do
    setup_new_listing_comparison

    get stock_path(@nl_base, new_listing: "hide")
    assert_response :success
    refute_includes response.body, "次新同行股", "hide 时首页不应包含次新同行"
    assert_includes response.body, "次新老同行", "hide 时老同行应保留"

    get industry_comparison_stock_path(@nl_base, page: 1, new_listing: "hide"),
        headers: { "Accept" => "application/json" }
    assert_response :success
    payload = JSON.parse(response.body)
    refute_includes payload["html"], "次新同行股", "hide 时分页接口不应返回次新同行"
    assert_includes payload["html"], "次新老同行"
  ensure
    @nl_base&.destroy! && @nl_old&.destroy! && @nl_recent&.destroy!
  end

  test "当前股票为次新股时 hide 过滤仍保留自身" do
    setup_new_listing_comparison
    recent_base = Stock.create!(symbol: "NL_SELF", name: "次新自身股", market: "CN", exchange: "SH",
                                sector: @nl_recent.sector, status: "active",
                                listing_date: Date.current - 6.months,
                                radar_dim_scores: { "roe" => 15 }, pyramid_total_score: 650)

    get stock_path(recent_base, new_listing: "hide")
    assert_response :success
    assert_includes response.body, "次新自身股", "当前次新股自身应豁免过滤保留在对比列表"
    refute_includes response.body, "次新同行股", "其他次新同行仍应被过滤"
  ensure
    recent_base&.destroy!
    @nl_base&.destroy! && @nl_old&.destroy! && @nl_recent&.destroy!
  end

  test "详情页无档案时不显示入口" do
    stock = Stock.create!(symbol: "DET_NOAR", name: "无档案测试", market: "CN", exchange: "SH",
                          sector: "消费", status: "active")
    sign_in users(:two)
    get stock_path(stock)
    assert_response :success
    refute_includes response.body, "企业质量档案"
  ensure
    stock&.destroy!
  end
end
