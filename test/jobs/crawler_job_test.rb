require "test_helper"

class CrawlerJobTest < ActiveSupport::TestCase
  test "已被看门狗判死的执行记录不再执行（防复活）" do
    execution = CrawlerExecution.create!(
      task_key: "a_finance", task_name: "爬取A股全套财务",
      status: "failed", executed_at: 13.hours.ago, duration: 0,
      message: "任务入队后超过 24.hours 未开始执行，已标记失败，请重新触发",
      finished_at: 1.hour.ago
    )

    CrawlerJob.perform_now(task_key: "a_finance", execution_id: execution.id, params: {})

    execution.reload
    # 保持看门狗写入的 failed 终态，不被 CrawlContext#start! 复活为 running
    assert_equal "failed", execution.status
    assert_not_nil execution.finished_at
    assert_includes execution.message, "未开始执行"
  end
end
