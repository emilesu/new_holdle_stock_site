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
    UserFavorite.where(stock_id: [@cn, @hk, @us, @cn_gas, @cn_semi].compact.map(&:id)).delete_all
    [@cn, @hk, @us, @cn_gas, @cn_semi].compact.each(&:destroy!)
  end

  test "index 警示徽章使用对应市场主题色" do
    # 会员墙（2ace2a9）后警示徽章仅会员视角渲染（非会员示例的标签打码），改用会员视角验证三市场主题色
    # 带 sector 筛选公用事业：setup 股票无分数排最后，避免被 fixtures 高分股挤出首页
    sign_in users(:two) # admin fixture，is_member? 为 true

    get pyramid_path(market: "CN", sector: "公用事业")
    assert_response :success
    assert_match(/bg-green-100 text-green-800/, response.body, "A股警示徽章应为绿色主题")
    # 警示徽章不应再使用灰色样式（限定在股票行内，避免页面其他区域干扰）
    assert_select ".stock-name span.bg-bg-mute.text-muted-2", count: 0, message: "警示徽章不应再使用灰色样式"

    get pyramid_path(market: "HK", sector: "公用事业")
    assert_response :success
    assert_match(/bg-amber-100 text-amber-800/, response.body, "港股警示徽章应为琥珀主题")

    get pyramid_path(market: "US", sector: "公用事业")
    assert_response :success
    assert_match(/bg-blue-100 text-blue-800/, response.body, "美股警示徽章应为蓝色主题")
  end

  test "index 渲染金字塔评分说明区（雷达图下方）" do
    # 非会员视角：说明区含权重表与「了解会员权益」CTA
    get pyramid_path(market: "CN")
    assert_response :success
    assert_select "h2", text: "金字塔评分怎么算"
    assert_select "table.hl-table tbody tr", count: 8, message: "权重表应有 8 项指标"
    assert_match(/了解会员权益/, response.body, "非会员应看到加入会员入口按钮")

    # 会员视角：CTA 变为「已解锁」
    sign_in users(:two) # admin fixture，is_member? 为 true
    get pyramid_path(market: "CN")
    assert_response :success
    assert_match(/已解锁/, response.body, "会员应看到已解锁状态")
    assert_no_match(/了解会员权益/, response.body, "会员不应看到加入会员按钮")
  end

  test "update_list 与 load_more 渲染成功且无灰色徽章" do
    # 会员墙后筛选 / 分页接口仅对会员开放，未登录一律 403
    sign_in users(:two)

    get "/pyramid/update_list", params: { market: "CN" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/bg-green-100 text-green-800/, response.body, "update_list 徽章应为 A股绿色主题")
    assert_select ".stock-name span.bg-bg-mute.text-muted-2", count: 0, message: "update_list 不应再使用灰色徽章"

    get "/pyramid/load_more", params: { market: "CN", page: 2 }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
  end

  test "update_sectors 返回板块列表、重置行业并同步会员提示" do
    sign_in users(:two)

    get "/pyramid/update_sectors", params: { market: "CN" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    # 三个 turbo_stream replace 目标都必须存在，保证 Turbo 局部刷新能定位到元素
    assert_match(/turbo-stream action="replace" target="sector-container"/, response.body)
    assert_match(/turbo-stream action="replace" target="industry-container"/, response.body)
    assert_match(/turbo-stream action="replace" target="sector-hint"/, response.body)
    # 会员可见板块选项（setup 中 CN 市场有「公用事业」板块）
    assert_match(/公用事业/, response.body)
    # 切换市场后行业下拉重置为禁用「全部」
    assert_match(/id="pyramid-industry"[^>]*disabled/, response.body)
    # 会员提示应隐藏
    assert_match(/id="sector-hint"[^>]*hidden/, response.body)
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

  test "非会员请求 update_industries 被会员墙拦截" do
    # 会员墙后非会员直接 403，不再返回行业列表
    get "/pyramid/update_industries", params: { market: "CN", sector: "公用事业" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
  end

  test "非会员 load_more 被会员墙拦截" do
    # 会员墙后非会员直接 403，industry 参数无从生效
    get "/pyramid/load_more", params: { market: "CN", sector: "公用事业", industry: "电力公用", page: 1 }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
  end

  test "已收藏股票在榜单显示市场主题色星标" do
    UserFavorite.create!(user: users(:two), stock: @cn)
    sign_in users(:two) # admin fixture，is_member? 为 true

    # A股：绿色主题星标（限 .stock-name 内，避免页面其他区域干扰）
    # 带 sector 筛选公用事业：setup 股票无分数排最后，避免被 fixtures 高分股挤出首页
    get pyramid_path(market: "CN", sector: "公用事业")
    assert_response :success
    assert_select ".stock-name span.text-green-600[title='已收藏']", count: 1, message: "已收藏的A股股票应渲染绿色主题星标"

    # 港股：琥珀主题星标，且同页未收藏股票不渲染星标
    UserFavorite.create!(user: users(:two), stock: @hk)
    get pyramid_path(market: "HK", sector: "公用事业")
    assert_response :success
    assert_select ".stock-name span.text-amber-600[title='已收藏']", count: 1, message: "已收藏的港股股票应渲染琥珀主题星标"
    assert_select ".stock-name span[title='已收藏']", count: 1, message: "未收藏股票不应渲染星标"
  end

  test "收藏星标覆盖未登录视角与 load_more 分页块" do
    UserFavorite.create!(user: users(:two), stock: @cn)

    # 未登录：不渲染星标
    get pyramid_path(market: "CN", sector: "公用事业")
    assert_response :success
    assert_select ".stock-name span[title='已收藏']", count: 0, message: "未登录不应渲染收藏星标"

    # load_more 分页块同样渲染星标
    sign_in users(:two)
    get "/pyramid/load_more", params: { market: "CN", page: 1 }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select ".stock-name span.text-green-600[title='已收藏']", count: 1, message: "load_more 分页块应渲染绿色主题星标"
  end
end
