require "test_helper"

module DataSources
  class CrawlerScopeTest < ActiveSupport::TestCase
    setup do
      @task = CrawlerRegistry.find("a_finance")
    end

    test "无参数时取任务所属市场全量并按 id 升序" do
      expected = Stock.where(market: "CN").order(:id).pluck(:id)
      assert_equal expected, CrawlerScope.resolve(task: @task, params: {}).pluck(:id)
    end

    test "stock_ids 优先于其它筛选条件" do
      us_ids = Stock.where(market: "US").pluck(:id)
      result = CrawlerScope.resolve(task: @task, params: { stock_ids: us_ids, only_failed: true })
      assert_equal us_ids.sort, result.pluck(:id)
    end

    test "after_stock_id 排除已处理部分（断点续跑）" do
      stocks = Stock.where(market: "CN").order(:id).to_a
      skip "需要至少两只 CN 股票" if stocks.size < 2

      result = CrawlerScope.resolve(task: @task, params: { after_stock_id: stocks.first.id })
      assert_equal stocks[1..].map(&:id).sort, result.pluck(:id)
    end

    test "limit 限制本次处理数量" do
      assert_equal 1, CrawlerScope.resolve(task: @task, params: { limit: 1 }).count
    end

    test "only_failed 只取最近一次同步失败的股票" do
      stock = Stock.where(market: "CN").first
      StockDataSyncState.create!(stock: stock, market: "CN", data_type: "financial",
                                status: "failed", retry_count: 1)

      assert_equal [ stock.id ], CrawlerScope.resolve(task: @task, params: { only_failed: true }).pluck(:id)
    end

    test "stale_after 排除刚刚成功同步的股票" do
      fresh = Stock.where(market: "CN").first
      StockDataSyncState.create!(stock: fresh, market: "CN", data_type: "financial",
                                status: "success", last_success_at: Time.current)

      ids = CrawlerScope.resolve(task: @task, params: { stale_after: 7 }).pluck(:id)
      refute_includes ids, fresh.id
    end

    test "未配置市场的任务默认取全量股票" do
      task = CrawlerRegistry.find("listing_date")
      all_ids = Stock.order(:id).pluck(:id)
      assert_equal all_ids, CrawlerScope.resolve(task: task, params: {}).pluck(:id)
    end
  end
end
