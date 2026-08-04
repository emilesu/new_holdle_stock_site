require "test_helper"

class PyramidsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # 无财务数据的股票必然打"数据<5年"警示标签，用于验证主题色徽章实际渲染
    @cn = Stock.create!(symbol: "PYR_CN", name: "徽章CN", market: "CN", exchange: "SH", sector: "公用事业", status: "active")
    @hk = Stock.create!(symbol: "PYR_HK", name: "徽章HK", market: "HK", exchange: "HKEX", sector: "公用事业", status: "active")
    @us = Stock.create!(symbol: "PYR_US", name: "徽章US", market: "US", exchange: "NASDAQ", sector: "公用事业", status: "active")
  end

  def teardown
    [@cn, @hk, @us].compact.each(&:destroy!)
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
end
