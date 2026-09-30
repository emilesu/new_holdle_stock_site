module DataSources
  # A股月K批量抓取编排器
  #
  # 原逻辑内联在 lib/tasks/monthly_bars.rake 中，只有 rake 入口、后台无法触发；
  # 抽成服务后可由后台按钮 / 定时任务 / rake 三处共用，并接入统一进度上报与同步状态记录。
  #
  # mode:
  #   :full        —— 全量重算并覆盖所有列（首次建库；前复权基准变更时使用）
  #   :incremental —— 已有历史行只更新前复权列，后复权列保持不动
  class MonthlyBarBatchService
    # 请求间隔（秒），与 SinaMonthlyBarService::REQUEST_INTERVAL 保持一致
    REQUEST_INTERVAL = SinaMonthlyBarService::REQUEST_INTERVAL

    class << self
      # 返回 { total:, success:, failed:, bars:, inserted: }
      def call(mode: :incremental, market: "CN", stock_ids: nil, after_stock_id: nil, limit: nil)
        mode = mode.to_s.to_sym
        stats = { total: 0, success: 0, failed: 0, bars: 0, inserted: 0 }

        stocks = target_stocks(mode, market, stock_ids, after_stock_id, limit)
        stats[:total] = stocks.count
        # 用服务真实的目标数量纠正进度分母：增量模式只处理「已有月K」的股票，
        # 与 CrawlerJob 按市场全量算出的分母不一致，不纠正进度永远到不了 100%
        CrawlContext.current&.start!(total_count: stats[:total])

        Rails.logger.info "[MonthlyBarBatch] 月K任务开始：mode=#{mode} market=#{market} 待处理 #{stats[:total]} 只"
        puts "月K任务开始：mode=#{mode}，待处理 #{stats[:total]} 只"

        stocks.each_with_index do |stock, index|
          ok = false
          begin
            result = SinaMonthlyBarService.refresh(stock, mode: mode)
            if result[:total].zero?
              stats[:failed] += 1
            else
              ok = true
              stats[:success] += 1
              stats[:bars] += result[:total]
              stats[:inserted] += result[:inserted]
            end
          rescue => e
            stats[:failed] += 1
            Rails.logger.error "[MonthlyBarBatch] #{stock.symbol} 失败：#{e.message}"
          end

          SyncStateRecorder.record(stock, :monthly_bar, ok: ok)
          CrawlContext.current&.tick(unit_id: stock.id, ok: ok)

          puts "  进度 [#{index + 1}/#{stats[:total]}] #{stock.symbol}" if ((index + 1) % 100).zero?
          sleep REQUEST_INTERVAL if REQUEST_INTERVAL.positive?
        end

        Rails.logger.info "[MonthlyBarBatch] 月K任务完成：#{summary(stats)}"
        stats
      end

      def summary(stats)
        "mode 总数=#{stats[:total]} 成功=#{stats[:success]} 失败=#{stats[:failed]} " \
          "月K=#{stats[:bars]} 新增行=#{stats[:inserted]}"
      end

      # 目标数量（供调用方在开始前写入进度基数）
      def target_total(mode, market: "CN", stock_ids: nil, after_stock_id: nil, limit: nil)
        target_stocks(mode.to_s.to_sym, market, stock_ids, after_stock_id, limit).count
      end

      private

      def target_stocks(mode, market, stock_ids, after_stock_id, limit)
        stocks = Stock.where(market: market)
        stocks = stocks.where(id: stock_ids) if stock_ids.present?
        stocks = stocks.where("stocks.id > ?", after_stock_id.to_i) if after_stock_id.present?
        # 增量只处理已有月K的股票，避免把全市场重跑一遍
        stocks = stocks.where(id: StockMonthlyBar.select(:stock_id)) if mode == :incremental
        stocks = stocks.order(:id)
        stocks = stocks.limit(limit.to_i) if limit.present?
        stocks
      end
    end
  end
end
