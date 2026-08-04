require "test_helper"

class ListingDateSyncMonitorJobTest < ActiveSupport::TestCase
  TASK_NAME = "上市日期同步"

  def setup
    @cn = Stock.create!(symbol: "MON_CN", name: "Monitor CN", market: "CN", exchange: "SH", sector: "消费", status: "active")
    @hk = Stock.create!(symbol: "MON_HK", name: "Monitor HK", market: "HK", exchange: "HKEX", sector: "消费", status: "active")
  end

  def teardown
    @cn&.destroy!
    @hk&.destroy!
    CrawlerExecution.where(task_name: TASK_NAME).delete_all
  end

  test "进程存活且无记录时创建 running 记录并展示进度" do
    total = Stock.where(market: %w[CN HK]).count
    ListingDateSyncMonitorJob.perform_now(process_alive: true)

    record = CrawlerExecution.where(task_name: TASK_NAME).first
    assert record, "应创建运行记录"
    assert_equal "running", record.status
    assert_includes record.message, "已同步 0 / #{total}"
    assert_includes record.message, "待同步"
  end

  test "进程存活时刷新已有 running 记录的进度" do
    total = Stock.where(market: %w[CN HK]).count
    listing = CrawlerExecution.create!(
      task_name: TASK_NAME, status: "running", message: "旧进度", duration: 0, executed_at: Time.current
    )

    # 同步一只后再次监控
    @hk.update!(listing_date: Date.current - 5.years)
    ListingDateSyncMonitorJob.perform_now(process_alive: true)

    listing.reload
    assert_includes listing.message, "已同步 1 / #{total}"
    assert_equal 1, CrawlerExecution.where(task_name: TASK_NAME).count, "不应重复创建记录"
  end

  test "进程退出时将 running 记录补全为 success" do
    executed_at = Time.current - 120
    listing = CrawlerExecution.create!(
      task_name: TASK_NAME, status: "running", message: "同步进行中", duration: 0, executed_at: executed_at
    )

    ListingDateSyncMonitorJob.perform_now(process_alive: false)

    listing.reload
    assert_equal "success", listing.status
    assert_includes listing.message, "上市日期同步结束"
    assert listing.duration > 0, "应记录耗时"
  end

  test "进程退出且无 running 记录时不创建新记录" do
    CrawlerExecution.create!(
      task_name: TASK_NAME, status: "success", message: "上次已完成", duration: 10, executed_at: Time.current - 3600
    )

    ListingDateSyncMonitorJob.perform_now(process_alive: false)

    assert_equal 1, CrawlerExecution.where(task_name: TASK_NAME).count, "不应覆盖已完成的记录"
  end
end
