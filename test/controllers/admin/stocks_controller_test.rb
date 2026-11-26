require "test_helper"

# 后台股票编辑：edit/update 动作与含特殊字符 symbol 的路由匹配
class Admin::StocksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:two) # role: admin
    @stock = Stock.create!(symbol: "BRK/B", exchange: "NYSE", market: "US",
                           name: "伯克希尔哈撒韦-B | Berkshire Hathaway Inc. Class B Common Stock")
  end

  test "含斜杠的美股代码能打开编辑页且表单回填正确" do
    get edit_admin_stock_path(@stock)
    assert_response :success
    assert_select "h1", "编辑股票"
    assert_select "option[value=?][selected]", "US"
    assert_select "input[name='stock[symbol]'][value=?]", "BRK/B"
  end

  test "update 保存字段并跳转详情页" do
    patch admin_stock_path(@stock), params: { stock: { sector: "金融服务", status: "listed" } }
    assert_redirected_to admin_stock_path(@stock)
    @stock.reload
    assert_equal "金融服务", @stock.sector
    assert_equal "listed", @stock.status
  end

  test "update 撞 symbol 唯一索引时回显表单而非 500" do
    Stock.create!(symbol: "BRK/A", exchange: "NYSE", market: "US", name: "伯克希尔哈撒韦-A")
    patch admin_stock_path(@stock), params: { stock: { symbol: "BRK/A" } }
    assert_response :unprocessable_entity
    assert_equal "BRK/B", @stock.reload.symbol, "重复提交不得落库"
    # 回显表单的 action 必须仍指向原股票（脏 symbol 会让 URL 指向被占用的另一只）
    assert_select "form[action=?]", "/admin/stocks/#{CGI.escape(@stock.to_param)}"
    assert_match(/已存在/, response.body)
  end

  test "update 拒绝服务端空必填字段且不落库" do
    patch admin_stock_path(@stock), params: { stock: { symbol: "  ", name: "x" } }
    assert_response :unprocessable_entity
    assert_equal "BRK/B", @stock.reload.symbol, "空 symbol 不得覆盖库内值"
    assert_select "form[action=?]", "/admin/stocks/#{CGI.escape(@stock.to_param)}"
  end
end
