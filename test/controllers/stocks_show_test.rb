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

  test "美股详情页不展示上市日期行" do
    stock = Stock.create!(symbol: "DET_US", name: "No List", market: "US", exchange: "NASDAQ",
                          sector: "科技", industry: "软件", status: "active")
    get stock_path(stock)
    assert_response :success
    refute_match(/上市日期/, response.body, "美股不支持上市日期，不应展示该行")
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
end
