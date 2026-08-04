require "test_helper"

class StocksShowTest < ActionDispatch::IntegrationTest
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
    assert_match(/bg-green-100 text-green-800"\s+title="财务数据不足5年，评分可靠性较低">数据&lt;5年</,
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
end
