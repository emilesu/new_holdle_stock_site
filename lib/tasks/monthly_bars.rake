# frozen_string_literal: true

# A股月K抓取任务（数据源：新浪 getKLineData + qfq.js / hfq.js 复权因子）
# ⚠️ 需启动 Rails 进程，按运维分工由用户手动执行
namespace :monthly_bars do
  desc "全量抓取 A股月K（不复权 + 前/后复权），首次建库或整只重算"
  task fetch_cn: :environment do
    run_monthly_bars_batch("monthly_bars_fetch_cn", :full)
  end

  desc "A股月K日常增量：已有历史行只重写前复权列，后复权只增不改"
  task refresh_cn: :environment do
    run_monthly_bars_batch("monthly_bars_refresh_cn", :incremental)
  end
end

def run_monthly_bars_batch(task_name, mode)
  started_at = Time.current
  stats = { total: 0, success: 0, failed: 0, bars: 0, inserted: 0 }

  stocks = Stock.where(market: "CN").order(:id)
  # 增量只处理已有月K的股票，避免把全市场重跑一遍
  stocks = stocks.where(id: StockMonthlyBar.select(:stock_id)) if mode == :incremental
  stats[:total] = stocks.count
  puts "月K任务开始：mode=#{mode}，待处理 #{stats[:total]} 只"

  stocks.find_each.with_index do |stock, index|
    begin
      result = DataSources::SinaMonthlyBarService.refresh(stock, mode: mode)
      if result[:total].zero?
        stats[:failed] += 1
      else
        stats[:success] += 1
        stats[:bars] += result[:total]
        stats[:inserted] += result[:inserted]
      end
    rescue => e
      stats[:failed] += 1
      Rails.logger.error "[monthly_bars] #{stock.symbol} 失败：#{e.message}"
    end

    puts "  进度 [#{index + 1}/#{stats[:total]}] #{stock.symbol}" if ((index + 1) % 100).zero?
    sleep DataSources::SinaMonthlyBarService::REQUEST_INTERVAL
  end

  duration = (Time.current - started_at).round(2)
  message = "mode=#{mode} 总数=#{stats[:total]} 成功=#{stats[:success]} 失败=#{stats[:failed]} " \
            "月K=#{stats[:bars]} 新增行=#{stats[:inserted]}"
  CrawlerExecution.create!(
    task_name: task_name,
    status: stats[:failed].zero? ? "success" : "failed",
    message: message,
    duration: duration,
    executed_at: Time.current
  )

  puts "月K任务完成：#{message}，耗时 #{duration}s"
end