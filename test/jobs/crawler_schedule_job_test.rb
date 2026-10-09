require "test_helper"

class CrawlerScheduleJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "已有任务在执行时跳过本次定时并留下 skipped 记录" do
    CrawlerExecution.create!(
      task_key: "a_finance", task_name: "爬取A股全套财务",
      status: "running", executed_at: Time.current, heartbeat_at: Time.current, duration: 0
    )

    assert_no_enqueued_jobs(only: CrawlerJob) do
      assert_difference -> { CrawlerExecution.where(status: "skipped").count }, 1 do
        CrawlerScheduleJob.perform_now(task_key: "a_stock_list")
      end
    end

    skipped = CrawlerExecution.order(:id).last
    assert_equal "a_stock_list", skipped.task_key
    assert_equal "schedule", skipped.trigger_source
    assert_equal "已有爬虫任务在执行，本次定时跳过", skipped.message
  end

  test "无任务执行时创建执行记录并入队" do
    assert_enqueued_with(job: CrawlerJob) do
      CrawlerScheduleJob.perform_now(task_key: "a_stock_list")
    end

    execution = CrawlerExecution.order(:id).last
    assert_equal "a_stock_list", execution.task_key
    assert_equal "schedule", execution.trigger_source
    assert_equal "running", execution.status
  end

  test "未知任务不创建记录" do
    assert_no_difference "CrawlerExecution.count" do
      CrawlerScheduleJob.perform_now(task_key: "not_exist")
    end
  end

  test "定时任务支持携带范围参数" do
    CrawlerScheduleJob.perform_now(task_key: "a_finance", params: { stale_after: 7 })

    assert_equal({ "stale_after" => 7 }, CrawlerExecution.order(:id).last.params)
  end
end
