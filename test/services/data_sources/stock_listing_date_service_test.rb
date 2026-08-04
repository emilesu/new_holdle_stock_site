require "test_helper"
require "minitest/mock"

module DataSources
  class StockListingDateServiceTest < ActiveSupport::TestCase
    def setup
      # 让 fixture 中的 CN 股票已有上市日期（事务性 fixture，测试后自动回滚），仅测试股票进入同步
      Stock.where(market: "CN").update_all(listing_date: Date.current - 10.years)
      @stock = Stock.create!(
        symbol: "LDT_CN", name: "Listing Date Test", market: "CN", exchange: "SH", sector: "消费", status: "active"
      )
    end

    def teardown
      @stock&.destroy!
    end

    # 构造 Faraday 响应对象（success?/status/body）
    def fake_response(body)
      Struct.new(:body) do
        def success? = true
        def status = 200
      end.new(body)
    end

    test "网络失败（重试耗尽）计入 failed 而非 skipped" do
      Faraday.stub(:get, ->(_url) { raise Faraday::ConnectionFailed, "connection refused" }) do
        result = DataSources::StockListingDateService.call(market: "CN")
        assert_equal 1, result[:failed], "网络失败应计入 failed"
        assert_equal 0, result[:updated]
      end
    end

    test "未来日期异常数据不写库并计入 skipped" do
      body = '{"result":{"data":[{"LISTING_DATE":"2099-01-01"}]}}'
      # 必须用 callable stub：minitest 对非 callable 值不处理调用方传入的 block，
      # 会导致 Faraday.get(url) do |req| ... end 中以 req=nil 执行 block 报错
      Faraday.stub(:get, ->(_url) { fake_response(body) }) do
        result = DataSources::StockListingDateService.call(market: "CN")
        assert_equal 1, result[:skipped], "未来日期应计入 skipped"
        assert_equal 0, result[:updated]
        assert_equal 0, result[:failed]
        assert_nil @stock.reload.listing_date, "未来日期不应写入数据库"
      end
    end
  end
end
