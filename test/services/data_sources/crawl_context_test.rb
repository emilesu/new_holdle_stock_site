require "test_helper"
require "minitest/mock"

module DataSources
  class CrawlContextTest < ActiveSupport::TestCase
    setup do
      @execution = CrawlerExecution.create!(
        task_key: "a_finance", task_name: "爬取A股全套财务",
        status: "running", executed_at: Time.current, duration: 0
      )
    end

    test "start! 初始化进度分母与心跳" do
      CrawlContext.new(execution: @execution).start!(total_count: 10)

      @execution.reload
      assert_equal 10, @execution.total_count
      assert_equal 0, @execution.processed_count
      assert_not_nil @execution.heartbeat_at
      assert_match "10", @execution.progress_message
    end

    test "tick 累计成功与失败，finish! 落库并保留断点" do
      stocks = Stock.order(:id).limit(2).to_a
      context = CrawlContext.new(execution: @execution)
      context.start!(total_count: 2)
      context.tick(unit_id: stocks.first.id, ok: true)
      context.tick(unit_id: stocks.second.id, ok: false)
      context.finish!(message: "全部处理完成")

      @execution.reload
      assert_equal "success", @execution.status
      assert_equal 2, @execution.processed_count
      assert_equal 1, @execution.success_count
      assert_equal 1, @execution.failed_count
      assert_equal stocks.second.id, @execution.checkpoint["last_unit_id"]
      assert_equal "全部处理完成", @execution.progress_message
      assert_not_nil @execution.finished_at
    end

    test "fail! 记录异常详情" do
      context = CrawlContext.new(execution: @execution)
      context.start!(total_count: 1)
      context.fail!(RuntimeError.new("接口超时"))

      @execution.reload
      assert_equal "failed", @execution.status
      assert_includes @execution.error_detail, "接口超时"
      assert_not_nil @execution.finished_at
    end

    test "with 在块结束后还原当前上下文" do
      context = CrawlContext.new(execution: @execution)
      CrawlContext.with(context) do
        assert_equal context, CrawlContext.current
      end
      assert_nil CrawlContext.current
    end

    test "进度写库失败不影响爬取主流程" do
      context = CrawlContext.new(execution: @execution)
      context.start!(total_count: 3)

      @execution.stub(:update_columns, ->(*) { raise ActiveRecord::StatementInvalid, "写库失败" }) do
        assert_nil context.tick(unit_id: 1, ok: true)
      end
    end
  end
end
