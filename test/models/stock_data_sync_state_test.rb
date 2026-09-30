require "test_helper"

class StockDataSyncStateTest < ActiveSupport::TestCase
  setup do
    @market = "CN"
    @stocks = Stock.where(market: @market).order(:id).to_a
    skip "需要 CN 股票样本" if @stocks.size < 2
  end

  test "coverage 区分正常 / 过期 / 从未同步 / 失败" do
    ok_stock = @stocks.first
    stale_stock = @stocks.second

    StockDataSyncState.create!(stock: ok_stock, market: @market, data_type: "financial",
                               status: "success", last_success_at: Time.current)
    StockDataSyncState.create!(stock: stale_stock, market: @market, data_type: "financial",
                               status: "success", last_success_at: 30.days.ago)

    coverage = StockDataSyncState.coverage(market: @market, data_type: "financial")

    assert_equal Stock.where(market: @market).count, coverage[:total]
    assert_equal 1, coverage[:ok]
    assert_equal 1, coverage[:stale]
    assert_equal 0, coverage[:failed]
    # 其余股票从未成功同步过（含表里完全没有记录的）；本用例已给两只股票都建了状态且都成功过
    assert_equal coverage[:total] - 2, coverage[:never]
  end

  test "coverage 把最近一次失败计入 failed" do
    failed_stock = @stocks.first
    StockDataSyncState.create!(stock: failed_stock, market: @market, data_type: "financial",
                               status: "failed", retry_count: 2)

    coverage = StockDataSyncState.coverage(market: @market, data_type: "financial")
    assert_equal 1, coverage[:failed]
    assert_equal 0, coverage[:ok]
  end

  test "target_stocks 支持 missing / stale / failed 三种范围" do
    stale_stock = @stocks.first
    failed_stock = @stocks.second

    StockDataSyncState.create!(stock: stale_stock, market: @market, data_type: "financial",
                               status: "success", last_success_at: 30.days.ago)
    StockDataSyncState.create!(stock: failed_stock, market: @market, data_type: "financial",
                               status: "failed", retry_count: 1)

    stale_ids = StockDataSyncState.target_stocks(market: @market, data_type: "financial", scope: "stale").pluck(:id)
    failed_ids = StockDataSyncState.target_stocks(market: @market, data_type: "financial", scope: "failed").pluck(:id)
    missing_ids = StockDataSyncState.target_stocks(market: @market, data_type: "financial", scope: "missing").pluck(:id)

    assert_equal [ stale_stock.id ], stale_ids
    assert_equal [ failed_stock.id ], failed_ids
    assert_not_includes missing_ids, stale_stock.id
    # failed_stock 抓取失败、从未成功过 → 落在「从未成功」范围内；与「最近失败」范围有意重叠：
    # 两个卡片点进去都能补抓，不会漏
    assert_includes missing_ids, failed_stock.id
  end

  test "target_stocks 默认返回市场全量" do
    assert_equal Stock.where(market: @market).order(:id).pluck(:id),
                 StockDataSyncState.target_stocks(market: @market, data_type: "financial", scope: "all").order(:id).pluck(:id)
  end

  test "过期阈值按数据类型区分" do
    assert_equal 7.days, StockDataSyncState.stale_after_for("financial")
    assert_equal 35.days, StockDataSyncState.stale_after_for("monthly_bar")
    assert_equal StockDataSyncState::DEFAULT_STALE_AFTER, StockDataSyncState.stale_after_for("unknown")
  end
end
