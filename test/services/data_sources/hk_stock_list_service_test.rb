require "test_helper"

class HkStockListServiceTest < ActiveSupport::TestCase
  setup do
    Stock.where(market: "HK").delete_all
    DataSources::HkStockListService.http_client = nil
  end

  teardown do
    DataSources::HkStockListService.http_client = nil
  end

  def build_success_response(body)
    resp = Object.new
    resp.define_singleton_method(:success?) { true }
    resp.define_singleton_method(:body) { body }
    resp
  end

  def build_failure_response(status = 500)
    resp = Object.new
    resp.define_singleton_method(:success?) { false }
    resp.define_singleton_method(:status) { status }
    resp
  end

  def build_timeout_client
    client = Object.new
    client.define_singleton_method(:get) { |*_args| raise Faraday::TimeoutError, "execution expired" }
    client
  end

  def build_sequence_client(responses)
    call_index = 0
    client = Object.new
    client.define_singleton_method(:get) do |*_args|
      resp = responses[call_index]
      call_index += 1
      if resp.respond_to?(:call)
        resp.call
      else
        resp
      end
    end
    client
  end

  # ====================================================
  # 测试常量定义
  # ====================================================
  test "常量定义完整" do
    assert DataSources::HkStockListService::MAIRUI_BASE_URL.present?
    assert DataSources::HkStockListService::EM_DATACENTER_URL.present?
    assert DataSources::HkStockListService::TIMEOUT > 0
    assert DataSources::HkStockListService::RETRY_TIMES >= 0
    assert DataSources::HkStockListService::REQUEST_INTERVAL >= 0
    assert DataSources::HkStockListService::EXCHANGE_MAPPING["HK"].present?
  end

  # ====================================================
  # 测试交易所映射
  # ====================================================
  test "交易所映射：HK -> 香港交易所" do
    assert_equal "香港交易所", DataSources::HkStockListService.send(:map_exchange, "HK")
  end

  test "交易所映射：未知代码返回原值" do
    assert_equal "NYSE", DataSources::HkStockListService.send(:map_exchange, "NYSE")
  end

  test "交易所映射：nil返回默认值" do
    assert_equal "香港交易所", DataSources::HkStockListService.send(:map_exchange, nil)
  end

  # ====================================================
  # 测试测试数据生成
  # ====================================================
  test "generate_test_data 返回正确格式" do
    data = DataSources::HkStockListService.send(:generate_test_data, 5)
    assert_equal 5, data.size
    data.each do |item|
      assert item[:symbol].present?
      assert item[:name].present?
      assert item[:exchange].present?
      assert item[:sector].present?
      assert item[:industry].present?
    end
  end

  test "generate_test_data 前两条数据正确" do
    data = DataSources::HkStockListService.send(:generate_test_data, 2)

    assert_equal "00001.HK", data[0][:symbol]
    assert_equal "长和", data[0][:name]
    assert_equal "香港交易所", data[0][:exchange]
    assert_equal "综合企业", data[0][:sector]
    assert_equal "00002.HK", data[1][:symbol]
    assert_equal "中电控股", data[1][:name]
  end

  # ====================================================
  # 测试 process_stock
  # ====================================================
  test "process_stock 新增港股" do
    item = { symbol: "00700.HK", name: "腾讯控股", exchange: "香港交易所", sector: "资讯科技业", industry: "软件及服务" }

    result = DataSources::HkStockListService.send(:process_stock, item)

    assert_equal :created, result
    stock = Stock.find_by(symbol: "00700.HK", market: "HK")
    assert stock.present?
    assert_equal "腾讯控股", stock.name
    assert_equal "香港交易所", stock.exchange
    assert_equal "资讯科技业", stock.sector
    assert_equal "软件及服务", stock.industry
    assert_equal "active", stock.status
  end

  test "process_stock 无变更跳过" do
    Stock.create!(symbol: "00005.HK", name: "汇丰控股", market: "HK",
                  exchange: "香港交易所", sector: "金融业", industry: "银行", status: "active")

    item = { symbol: "00005.HK", name: "汇丰控股", exchange: "香港交易所", sector: "金融业", industry: "银行" }

    result = DataSources::HkStockListService.send(:process_stock, item)
    assert_equal :skipped, result
  end

  test "process_stock 有变更时更新" do
    Stock.create!(symbol: "00005.HK", name: "HSBC", market: "HK",
                  exchange: "香港交易所", sector: "金融业", industry: "银行", status: "active")

    item = { symbol: "00005.HK", name: "汇丰控股", exchange: "香港交易所", sector: "金融业", industry: "银行" }

    result = DataSources::HkStockListService.send(:process_stock, item)
    assert_equal :updated, result

    stock = Stock.find_by(symbol: "00005.HK", market: "HK")
    assert_equal "汇丰控股", stock.name
  end

  test "process_stock symbol为空返回failed" do
    result = DataSources::HkStockListService.send(:process_stock, { symbol: nil, name: "Test", exchange: "HK", sector: "其他", industry: "其他" })
    assert_equal :failed, result
  end

  test "process_stock 行业变更触发更新" do
    Stock.create!(symbol: "00700.HK", name: "腾讯控股", market: "HK",
                  exchange: "香港交易所", sector: "综合企业", industry: "综合企业", status: "active")

    item = { symbol: "00700.HK", name: "腾讯控股", exchange: "香港交易所", sector: "资讯科技业", industry: "软件及服务" }

    result = DataSources::HkStockListService.send(:process_stock, item)
    assert_equal :updated, result

    stock = Stock.find_by(symbol: "00700.HK", market: "HK")
    assert_equal "资讯科技业", stock.sector
  end

  # ====================================================
  # 测试 fetch_hk_list_from_mairui
  # ====================================================
  test "mairui 成功解析数据" do
    resp = build_success_response('[{"dm":"00001.HK","mc":"长和","jys":"HK"},{"dm":"00002.HK","mc":"中电控股","jys":"HK"}]')
    client = Object.new
    client.define_singleton_method(:get) { |*_args| resp }
    DataSources::HkStockListService.http_client = client

    result = DataSources::HkStockListService.send(:fetch_hk_list_from_mairui)
    assert_equal 2, result.size
    assert_equal "00001.HK", result[0][:symbol]
    assert_equal "长和", result[0][:name]
    assert_equal "香港交易所", result[0][:exchange]
  end

  test "mairui 空数组返回" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_success_response("[]")])
    assert_equal 0, DataSources::HkStockListService.send(:fetch_hk_list_from_mairui).size
  end

  test "mairui 请求失败返回空" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_failure_response(500)])
    assert_equal 0, DataSources::HkStockListService.send(:fetch_hk_list_from_mairui).size
  end

  test "mairui JSON解析失败返回空" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_success_response("invalid json")])
    assert_equal 0, DataSources::HkStockListService.send(:fetch_hk_list_from_mairui).size
  end

  test "mairui 网络超时返回空" do
    DataSources::HkStockListService.http_client = build_timeout_client
    result = DataSources::HkStockListService.send(:fetch_hk_list_from_mairui)
    assert_equal 0, result.size
  end

  test "mairui 过滤无效数据" do
    resp = build_success_response('[{"dm":"00001.HK","mc":"长和","jys":"HK"},{"dm":null,"mc":"无效","jys":"HK"}]')
    client = Object.new
    client.define_singleton_method(:get) { |*_args| resp }
    DataSources::HkStockListService.http_client = client

    result = DataSources::HkStockListService.send(:fetch_hk_list_from_mairui)
    assert_equal 1, result.size
    assert_equal "00001.HK", result[0][:symbol]
  end

  test "mairui 非数组返回空" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_success_response('{"error":"not array"}')])
    assert_equal 0, DataSources::HkStockListService.send(:fetch_hk_list_from_mairui).size
  end

  # ====================================================
  # 测试恒生行业分类映射表 HK_INDUSTRY_MAPPING
  # ====================================================
  test "HK_INDUSTRY_MAPPING 所有项结构完整" do
    DataSources::HkStockListService::HK_INDUSTRY_MAPPING.each do |raw_name, mapping|
      assert mapping[:sector].present?, "#{raw_name} 缺少sector"
      assert mapping[:industry].present?, "#{raw_name} 缺少industry"
    end
  end

  test "HK_INDUSTRY_MAPPING 关键映射正确" do
    mapping = DataSources::HkStockListService::HK_INDUSTRY_MAPPING

    assert_equal "资讯科技业", mapping["软件服务"][:sector]
    assert_equal "软件及服务", mapping["软件服务"][:industry]

    assert_equal "金融业", mapping["银行"][:sector]
    assert_equal "银行", mapping["银行"][:industry]

    assert_equal "地产建筑业", mapping["地产"][:sector]
    assert_equal "地产发展", mapping["地产"][:industry]
  end

  test "HK_INDUSTRY_MAPPING 覆盖高频EM行业名" do
    mapping = DataSources::HkStockListService::HK_INDUSTRY_MAPPING

    key_names = %w[软件服务 银行 保险 地产 建筑 工业工程 公用事业 综合企业
                   电讯服务 汽车 媒体及娱乐 旅游及消闲设施 石油及天然气
                   煤炭 食物饮品 药品及生物科技 其他金融 专业零售 半导体]

    key_names.each do |name|
      assert mapping.key?(name), "缺少高频行业映射: #{name}"
    end
  end

  test "INDUSTRY_TO_SECTOR 反查表完整" do
    lookup = DataSources::HkStockListService::INDUSTRY_TO_SECTOR

    assert_equal "资讯科技业", lookup["软件及服务"]
    assert_equal "金融业", lookup["银行"]
    assert_equal "地产建筑业", lookup["地产发展"]
    assert_equal "非必需性消费", lookup["汽车"]
    assert_equal "综合企业", lookup["综合企业"]
  end

  test "INDUSTRY_TO_SECTOR 不重复" do
    lookup = DataSources::HkStockListService::INDUSTRY_TO_SECTOR
    assert_equal lookup.keys.uniq.size, lookup.size
  end

  # ====================================================
  # 测试 fetch_hk_industry - 未映射行业名
  # ====================================================
  test "em 未映射的行业名归入其他" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_success_response('{"result":{"data":[{"BELONG_INDUSTRY":"未知行业XYZ"}]},"success":true}')])

    result = DataSources::HkStockListService.send(:fetch_hk_industry, "99999.HK")
    assert_equal "其他", result[:sector]
    assert_equal "其他", result[:industry]
  end

  test "em 成功获取行业" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_success_response('{"result":{"data":[{"BELONG_INDUSTRY":"软件服务"}]},"success":true}')])

    result = DataSources::HkStockListService.send(:fetch_hk_industry, "00700.HK")
    assert_equal "资讯科技业", result[:sector]
    assert_equal "软件及服务", result[:industry]
  end

  test "em 行业为空返回其他" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_success_response('{"result":{"data":[{}]},"success":true}')])

    assert_equal "其他", DataSources::HkStockListService.send(:fetch_hk_industry, "99999.HK")[:sector]
  end

  test "em 请求失败返回其他" do
    DataSources::HkStockListService.http_client = build_sequence_client([build_failure_response(500)])

    assert_equal "其他", DataSources::HkStockListService.send(:fetch_hk_industry, "00700.HK")[:sector]
  end

  test "em 网络超时返回其他" do
    DataSources::HkStockListService.http_client = build_timeout_client

    assert_equal "其他", DataSources::HkStockListService.send(:fetch_hk_industry, "00700.HK")[:sector]
  end

  # ====================================================
  # 测试完整的 call 方法
  # ====================================================
  test "call 方法正常流程" do
    responses = [
      build_success_response('[{"dm":"00001.HK","mc":"长和","jys":"HK"},{"dm":"00002.HK","mc":"中电控股","jys":"HK"}]'),
      build_success_response('{"result":{"data":[{"BELONG_INDUSTRY":"综合企业"}]},"success":true}'),
      build_success_response('{"result":{"data":[{"BELONG_INDUSTRY":"公用事业"}]},"success":true}')
    ]
    DataSources::HkStockListService.http_client = build_sequence_client(responses)

    stats = DataSources::HkStockListService.call

    assert_equal 2, stats[:total]
    assert_equal 2, stats[:created]

    stock1 = Stock.find_by(symbol: "00001.HK", market: "HK")
    assert stock1.present?
    assert_equal "长和", stock1.name
    assert_equal "综合企业", stock1.sector

    stock2 = Stock.find_by(symbol: "00002.HK", market: "HK")
    assert stock2.present?
    assert_equal "中电控股", stock2.name
    assert_equal "公用事业", stock2.sector
  end

  test "call 方法API不可用时使用测试数据" do
    DataSources::HkStockListService.http_client = build_timeout_client

    stats = DataSources::HkStockListService.call(size: 5)

    assert_equal 5, stats[:total]
    assert_equal 5, Stock.where(market: "HK").count
  end

  test "call 方法数据去重" do
    Stock.create!(symbol: "00001.HK", name: "旧名称", market: "HK",
                  exchange: "香港交易所", sector: "旧行业", industry: "旧行业", status: "active")

    responses = [
      build_success_response('[{"dm":"00001.HK","mc":"长和","jys":"HK"}]'),
      build_success_response('{"result":{"data":[{"BELONG_INDUSTRY":"综合企业"}]},"success":true}')
    ]
    DataSources::HkStockListService.http_client = build_sequence_client(responses)

    stats = DataSources::HkStockListService.call

    assert_equal 1, stats[:total]
    assert_equal 1, stats[:updated]
    assert_equal 0, stats[:created]
    assert_equal 1, Stock.where(market: "HK", symbol: "00001.HK").count
  end
end