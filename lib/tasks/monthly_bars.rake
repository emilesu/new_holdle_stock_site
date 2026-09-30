# frozen_string_literal: true

# A股月K抓取任务（数据源：新浪 getKLineData + qfq.js / hfq.js 复权因子）
# ⚠️ 需启动 Rails 进程，按运维分工由用户手动执行
#
# 编排逻辑已抽到 DataSources::MonthlyBarBatchService（后台按钮与定时任务共用同一入口），
# 本文件只保留「创建执行记录 + 调用服务 + 收尾」的薄壳。
namespace :monthly_bars do
  desc "全量抓取 A股月K（不复权 + 前/后复权），首次建库或整只重算"
  task fetch_cn: :environment do
    run_monthly_bars_batch("monthly_bars_fetch_cn", "A股月K全量重建", :full)
  end

  desc "A股月K日常增量：已有历史行只重写前复权列，后复权只增不改"
  task refresh_cn: :environment do
    run_monthly_bars_batch("monthly_bars_refresh_cn", "A股月K增量", :incremental)
  end
end

def run_monthly_bars_batch(task_key, task_name, mode)
  execution = CrawlerExecution.create!(
    task_key: task_key,
    task_name: task_name,
    trigger_source: "manual",
    market: "CN",
    status: "running",
    message: "任务已提交，正在执行中...",
    duration: 0,
    executed_at: Time.current
  )

  context = DataSources::CrawlContext.new(execution: execution)

  DataSources::CrawlContext.with(context) do
    begin
      context.start!(total_count: DataSources::MonthlyBarBatchService.target_total(mode))
      stats = DataSources::MonthlyBarBatchService.call(mode: mode)
      context.finish!(message: "#{task_name}完成：#{DataSources::MonthlyBarBatchService.summary(stats)}")
      puts "月K任务完成：#{DataSources::MonthlyBarBatchService.summary(stats)}"
    rescue => e
      context.fail!(e)
      raise
    end
  end
end
