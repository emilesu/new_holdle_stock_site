require "test_helper"

module DataSources
  class AStockListServiceTest < ActiveSupport::TestCase
    # 测试使用 SH600519 等带市场前缀的 symbol，与 fixture（000001/600036 等纯数字）不冲突；
    # 事务性 fixture 自动回滚，无需清理数据库
    def fake_response(body, success: true)
      resp = Object.new
      resp.define_singleton_method(:success?) { success }
      resp.define_singleton_method(:status) { success ? 200 : 500 }
      resp.define_singleton_method(:body) { body }
      resp
    end

    # ====================================================
    # 测试 secucode_from_symbol
    # ====================================================
    test "secucode_from_symbol 沪市转换" do
      assert_equal "600519.SH", AStockListService.send(:secucode_from_symbol, "SH600519")
    end

    test "secucode_from_symbol 深市转换" do
      assert_equal "000001.SZ", AStockListService.send(:secucode_from_symbol, "SZ000001")
    end

    test "secucode_from_symbol 北交所转换" do
      assert_equal "920000.BJ", AStockListService.send(:secucode_from_symbol, "BJ920000")
    end

    # ====================================================
    # 测试 fetch_listing_date（东方财富 F10 组织资料报表）
    # ====================================================
    test "fetch_listing_date 正常返回上市日期" do
      Faraday.stub(:get, ->(_url) { fake_response('{"result":{"data":[{"LISTING_DATE":"2001-08-27"}]}}') }) do
        date = AStockListService.send(:fetch_listing_date, "600519.SH")
        assert_equal Date.new(2001, 8, 27), date
      end
    end

    test "fetch_listing_date 未来日期视为异常返回nil" do
      Faraday.stub(:get, ->(_url) { fake_response('{"result":{"data":[{"LISTING_DATE":"2099-01-01"}]}}') }) do
        assert_nil AStockListService.send(:fetch_listing_date, "600519.SH")
      end
    end

    test "fetch_listing_date 空数据返回nil" do
      Faraday.stub(:get, ->(_url) { fake_response('{"result":{"data":[]}}') }) do
        assert_nil AStockListService.send(:fetch_listing_date, "600519.SH")
      end
    end

    test "fetch_listing_date 请求失败（非2xx）返回nil" do
      Faraday.stub(:get, ->(_url) { fake_response("", success: false) }) do
        assert_nil AStockListService.send(:fetch_listing_date, "600519.SH")
      end
    end

    test "fetch_listing_date 网络失败重试耗尽返回nil" do
      Faraday.stub(:get, ->(_url) { raise Faraday::ConnectionFailed, "connection refused" }) do
        assert_nil AStockListService.send(:fetch_listing_date, "600519.SH")
      end
    end

    # ====================================================
    # 测试 process_stock（新增/更新/跳过）
    # ====================================================
    test "process_stock 新增A股并填充上市日期与拼音首字母" do
      calls = 0
      Faraday.stub(:get, ->(url) {
        assert_equal EastmoneyDatacenter::BASE_URL, url, "新增股票应请求 F10 上市日期接口"
        calls += 1
        fake_response('{"result":{"data":[{"LISTING_DATE":"2001-08-27"}]},"success":true}')
      }) do
        item = { "symbol" => "SH600519", "name" => "贵州茅台", "exchange" => "上海证券交易所",
                 "sector" => "食品饮料", "main_business" => "饮料制造" }

        result = AStockListService.send(:process_stock, item)
        assert_equal :created, result
      end
      assert_equal 1, calls

      stock = Stock.find_by(symbol: "SH600519", market: "CN")
      assert stock.present?
      assert_equal Date.new(2001, 8, 27), stock.listing_date
      assert_equal "GZMT", stock.pinyin_initials
    end

    test "process_stock 存量A股不请求F10且listing_date保持不变" do
      Stock.create!(symbol: "SH600519", name: "贵州茅台", market: "CN",
                    exchange: "上海证券交易所", sector: "食品饮料", industry: "饮料制造", status: "active")

      calls = 0
      Faraday.stub(:get, ->(_url) { calls += 1; raise "存量股票不应发起任何请求" }) do
        item = { "symbol" => "SH600519", "name" => "贵州茅台", "exchange" => "上海证券交易所",
                 "sector" => "食品饮料", "main_business" => "饮料制造" }

        result = AStockListService.send(:process_stock, item)
        assert_equal :skipped, result
      end
      assert_equal 0, calls
      assert_nil Stock.find_by(symbol: "SH600519", market: "CN").listing_date
    end

    test "process_stock 存量A股有变更时更新且不请求F10" do
      Stock.create!(symbol: "SH600519", name: "MAOTAI", market: "CN",
                    exchange: "上海证券交易所", sector: "食品饮料", industry: "饮料制造", status: "active")

      calls = 0
      Faraday.stub(:get, ->(_url) { calls += 1; raise "存量股票不应发起任何请求" }) do
        item = { "symbol" => "SH600519", "name" => "贵州茅台", "exchange" => "上海证券交易所",
                 "sector" => "食品饮料", "main_business" => "饮料制造" }

        result = AStockListService.send(:process_stock, item)
        assert_equal :updated, result
      end
      assert_equal 0, calls

      stock = Stock.find_by(symbol: "SH600519", market: "CN")
      assert_equal "贵州茅台", stock.name
      assert_nil stock.listing_date
    end

    test "process_stock 新增A股F10请求失败仍创建且listing_date为空" do
      Faraday.stub(:get, ->(_url) { fake_response("", success: false) }) do
        item = { "symbol" => "SH600519", "name" => "贵州茅台", "exchange" => "上海证券交易所",
                 "sector" => "食品饮料", "main_business" => "饮料制造" }

        result = AStockListService.send(:process_stock, item)
        assert_equal :created, result
      end

      stock = Stock.find_by(symbol: "SH600519", market: "CN")
      assert stock.present?
      assert_nil stock.listing_date, "F10 请求失败不应阻断股票创建"
    end

    test "process_stock symbol为空返回failed" do
      result = AStockListService.send(:process_stock, { "symbol" => nil, "name" => "Test",
                                                        "exchange" => "上海证券交易所", "sector" => "其他", "main_business" => "其他" })
      assert_equal :failed, result
    end
  end
end
