require "test_helper"

class PyramidsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    # 无财务数据的股票必然打"数据<5年"警示标签，用于验证主题色徽章实际渲染
    @cn = Stock.create!(symbol: "PYR_CN", name: "徽章CN", market: "CN", exchange: "SH", sector: "公用事业", industry: "电力公用", status: "active")
    @hk = Stock.create!(symbol: "PYR_HK", name: "徽章HK", market: "HK", exchange: "HKEX", sector: "公用事业", industry: "电力公用", status: "active")
    @us = Stock.create!(symbol: "PYR_US", name: "徽章US", market: "US", exchange: "NASDAQ", sector: "公用事业", industry: "电力公用", status: "active")
    # 行业过滤测试专用股票
    @cn_gas = Stock.create!(symbol: "PYR_CN_GAS", name: "燃气测试", market: "CN", exchange: "SH", sector: "公用事业", industry: "燃气公用", status: "active")
    @cn_semi = Stock.create!(symbol: "PYR_CN_SEMI", name: "半导体测试", market: "CN", exchange: "SH", sector: "科技", industry: "半导体", status: "active")
  end

  def teardown
    [@cn, @hk, @us, @cn_gas, @cn_semi].compact.each(&:destroy!)
  end

  test "index 警示徽章使用对应市场主题色" do
    get pyramid_path(market: "CN")
    assert_response :success
    assert_match(/bg-green-100 text-green-800/, response.body, "A股警示徽章应为绿色主题")
    # 警示徽章不应再使用灰色样式（限定在股票行内，避免页面其他区域干扰）
    assert_select ".stock-name span.bg-bg-mute.text-muted-2", count: 0, message: "警示徽章不应再使用灰色样式"

    get pyramid_path(market: "HK")
    assert_response :success
    assert_match(/bg-amber-100 text-amber-800/, response.body, "港股警示徽章应为琥珀主题")

    get pyramid_path(market: "US")
    assert_response :success
    assert_match(/bg-blue-100 text-blue-800/, response.body, "美股警示徽章应为蓝色主题")
  end

  test "update_list 与 load_more 渲染成功且无灰色徽章" do
    get "/pyramid/update_list", params: { market: "CN" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/bg-green-100 text-green-800/, response.body, "update_list 徽章应为 A股绿色主题")
    assert_select ".stock-name span.bg-bg-mute.text-muted-2", count: 0, message: "update_list 不应再使用灰色徽章"

    get "/pyramid/load_more", params: { market: "CN", page: 2 }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
  end

  test "会员 index 带 industry 参数只返回匹配行业的股票" do
    sign_in users(:two) # admin fixture，is_member? 为 true

    get pyramid_path(market: "CN", sector: "公用事业", industry: "电力公用")
    assert_response :success
    assert_match(/data-stock-symbol="PYR_CN"/, response.body)
    assert_no_match(/data-stock-symbol="PYR_CN_GAS"/, response.body, "行业过滤后不应包含其他行业的股票")
  end

  test "会员 update_industries 返回该板块下的行业列表" do
    sign_in users(:two)

    get "/pyramid/update_industries", params: { market: "CN", sector: "公用事业" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/电力公用/, response.body)
    assert_match(/燃气公用/, response.body)
    assert_no_match(/半导体/, response.body, "不应包含其他板块下的行业")
  end

  test "会员 update_list 带 industry 过滤渲染成功" do
    sign_in users(:two)

    get "/pyramid/update_list", params: { market: "CN", sector: "公用事业", industry: "电力公用" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/data-stock-symbol="PYR_CN"/, response.body)
    assert_no_match(/data-stock-symbol="PYR_CN_GAS"/, response.body, "行业过滤后不应包含其他行业的股票")
    assert_match(/data-industry="电力公用"/, response.body, "sentinel 应回显当前行业用于无限滚动")
  end

  test "非会员请求 update_industries 返回空行业列表" do
    get "/pyramid/update_industries", params: { market: "CN", sector: "公用事业" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    # 非会员不应返回任何行业选项（仅「全部」）
    assert_no_match(/电力公用/, response.body)
    assert_no_match(/燃气公用/, response.body)
    # 非会员渲染的下拉应处于 disabled 状态
    assert_match(/id="pyramid-industry"[^>]*disabled/, response.body)
  end

  test "非会员 load_more 带 industry 参数被忽略" do
    get "/pyramid/load_more", params: { market: "CN", sector: "公用事业", industry: "电力公用", page: 1 }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    # 非会员强制 industry=''，公用事业板块下燃气股也应出现
    assert_match(/data-stock-symbol="PYR_CN_GAS"/, response.body)
  end
end
