require "test_helper"

class CrawlerWatchdogJobTest < ActiveSupport::TestCase
  test "心跳停滞的 running 记录被标记失败并保留断点" do
    stale = create_execution(status: "running", heartbeat_at: 15.minutes.ago,
                             checkpoint: { "last_unit_id" => 123 })

    CrawlerWatchdogJob.perform_now

    stale.reload
    assert_equal "failed", stale.status
    assert_equal 123, stale.checkpoint["last_unit_id"]
    assert_not_nil stale.finished_at
    assert_includes stale.message, "中断"
  end

  test "心跳正常的 running 记录不受影响" do
    fresh = create_execution(status: "running", heartbeat_at: Time.current)

    CrawlerWatchdogJob.perform_now

    assert_equal "running", fresh.reload.status
    assert_nil fresh.finished_at
  end

  test "尚未开始执行（无心跳）的排队记录不被误判" do
    queued = create_execution(status: "running", heartbeat_at: nil)

    CrawlerWatchdogJob.perform_now

    assert_equal "running", queued.reload.status
  end

  test "入队后长时间未开始执行的记录被标记失败" do
    stuck = create_execution(status: "running", heartbeat_at: nil,
                             executed_at: CrawlerExecution::QUEUE_TIMEOUT.ago - 1.minute)

    CrawlerWatchdogJob.perform_now

    stuck.reload
    assert_equal "failed", stuck.status
    assert_includes stuck.message, "未开始执行"
  end

  test "已完成的记录不受影响" do
    done = create_execution(status: "success", heartbeat_at: 1.hour.ago, finished_at: 1.hour.ago)

    CrawlerWatchdogJob.perform_now

    assert_equal "success", done.reload.status
  end

  private

  def create_execution(status:, heartbeat_at:, checkpoint: {}, finished_at: nil,
                       executed_at: 15.minutes.ago)
    CrawlerExecution.create!(
      task_key: "a_finance", task_name: "爬取A股全套财务",
      status: status, executed_at: executed_at, duration: 0,
      heartbeat_at: heartbeat_at, checkpoint: checkpoint, finished_at: finished_at
    )
  end
end
