require "test_helper"

module DataSources
  class NasdaqStockListServiceTest < ActiveSupport::TestCase
    # 构造 Faraday 响应对象（success?/status/body）
    def fake_response(body)
      Struct.new(:body) do
        def success? = true
        def status = 200
      end.new(body)
    end

    # 仅 NASDAQ 端点返回列表数据，NYSE/AMEX 返回空行，避免同一样本被三个交易所反复更新
    def stub_get(rows, yahoo_handler)
      list_body = { "data" => { "totalrecords" => rows.size, "table" => { "rows" => rows } } }.to_json
      ->(url, *_rest) do
        if url.include?("api.nasdaq.com")
          rows_url = url.include?("exchange=NASDAQ") ? list_body : empty_list_body
          fake_response(rows_url)
        else
          yahoo_handler.call(url)
        end
      end
    end

    def empty_list_body
      { "data" => { "totalrecords" => 0, "table" => { "rows" => [] } } }.to_json
    end

    test "新收录美股入库时抓取 Yahoo firstTradeDate 补上市日期" do
      rows = [{ "symbol" => "NDT01", "name" => "Nasdaq Date Test 01" }]
      # AAPL 真实 firstTradeDate=345479400 → 1980-12-12（美东时间）
      yahoo = ->(_url) { fake_response('{"chart":{"result":[{"meta":{"firstTradeDate":345479400}}],"error":null}}') }

      Faraday.stub(:get, stub_get(rows, yahoo)) do
        stats = DataSources::NasdaqStockListService.call
        assert_equal 1, stats[:created]
      end

      stock = Stock.find_by(market: "US", symbol: "NDT01")
      assert_not_nil stock
      assert_equal Date.new(1980, 12, 12), stock.listing_date, "新收录美股应在入库时补上市日期"
    ensure
      Stock.where(market: "US", symbol: "NDT01").destroy_all
    end

    test "上市日期抓取失败不阻断美股入库" do
      rows = [{ "symbol" => "NDT02", "name" => "Nasdaq Date Test 02" }]
      yahoo = ->(_url) { raise Faraday::ConnectionFailed, "connection refused" }

      Faraday.stub(:get, stub_get(rows, yahoo)) do
        stats = DataSources::NasdaqStockListService.call
        assert_equal 1, stats[:created], "Yahoo 抓取失败时股票仍应入库"
      end

      stock = Stock.find_by(market: "US", symbol: "NDT02")
      assert_not_nil stock
      assert_nil stock.listing_date, "抓取失败时上市日期留空，由同步任务兜底"
    ensure
      Stock.where(market: "US", symbol: "NDT02").destroy_all
    end

    test "存量美股不重复抓取上市日期" do
      existing = Stock.create!(
        symbol: "NDT03", name: "Nasdaq Date Test 03", market: "US", exchange: "NASDAQ", status: "listed"
      )
      yahoo_called = false
      yahoo = ->(_url) do
        yahoo_called = true
        fake_response('{"chart":{"result":[{"meta":{"firstTradeDate":345479400}}],"error":null}}')
      end
      rows = [{ "symbol" => "NDT03", "name" => "Nasdaq Date Test 03" }]

      Faraday.stub(:get, stub_get(rows, yahoo)) do
        stats = DataSources::NasdaqStockListService.call
        assert_equal 0, stats[:created]
      end

      assert_not yahoo_called, "存量股票不应触发 Yahoo 上市日期请求"
      assert_nil existing.reload.listing_date
    ensure
      Stock.where(market: "US", symbol: "NDT03").destroy_all
    end
  end
end
