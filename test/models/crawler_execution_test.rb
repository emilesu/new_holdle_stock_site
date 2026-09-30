require "test_helper"

class CrawlerExecutionTest < ActiveSupport::TestCase
  test "progress_percent 在分母未知时返回 nil" do
    execution = build_execution(total_count: 0, processed_count: 5)
    assert_nil execution.progress_percent
  end

  test "progress_percent 按已处理 / 目标总数计算" do
    execution = build_execution(total_count: 8, processed_count: 2)
    assert_equal 25, execution.progress_percent
  end

  test "resumable? 仅有断点 unit_id 时为真" do
    assert build_execution(checkpoint: { "last_unit_id" => 9 }).resumable?
    refute build_execution(checkpoint: {}).resumable?
  end

  test "stale? 只在心跳超时的执行中记录上为真" do
    assert build_execution(status: "running", heartbeat_at: 20.minutes.ago).stale?
    refute build_execution(status: "running", heartbeat_at: Time.current).stale?
    refute build_execution(status: "success", heartbeat_at: 20.minutes.ago).stale?
  end

  test "by_task 与 for_market 支持筛选" do
    CrawlerExecution.create!(task_key: "a_finance", task_name: "A股财务", market: "CN",
                             status: "success", executed_at: Time.current, duration: 0)
    CrawlerExecution.create!(task_key: "hk_finance", task_name: "港股财务", market: "HK",
                             status: "success", executed_at: Time.current, duration: 0)

    assert_equal 1, CrawlerExecution.by_task("a_finance").count
    assert_equal 1, CrawlerExecution.for_market("HK").count
    assert_equal 0, CrawlerExecution.running.count
  end

  private

  def build_execution(**attrs)
    defaults = { task_key: "a_finance", task_name: "爬取A股全套财务",
                 status: "running", executed_at: Time.current, duration: 0 }
    CrawlerExecution.new(**defaults.merge(attrs))
  end
end
