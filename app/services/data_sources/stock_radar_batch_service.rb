module DataSources
  # 雷达维度缓存批量刷新服务
  # 支持全量重算和增量更新两种模式
  class StockRadarBatchService
    BATCH_SIZE = 100  # 分批处理大小，避免内存溢出

    class << self
      # 主入口方法
      # @param full_recalc [Boolean] true=全量刷新所有股票，false=仅刷新缓存缺失或过期的股票
      # @return [Hash] 统计结果 { total: Integer, updated: Integer, skipped: Integer, failed: Integer }
      def call(full_recalc: false)
        puts "🔄 开始#{full_recalc ? '全量' : '增量'}刷新雷达维度缓存..."

        # 根据模式选择股票
        stocks = if full_recalc
          Stock.all
        else
          # 增量模式：缓存为空或金字塔分数超过30天未更新的股票
          Stock.where(
            "radar_dim_scores IS NULL OR radar_dim_scores = '{}' OR last_pyramid_calc_at < ?",
            30.days.ago
          )
        end

        # 初始化统计数据
        stats = {
          total: stocks.count,
          updated: 0,
          skipped: 0,
          failed: 0
        }

        puts "📊 待处理股票总数: #{stats[:total]}"

        # 分批遍历处理
        stocks.find_each(batch_size: BATCH_SIZE) do |stock|
          begin
            result = StockRadarSingleService.call(stock)

            # 更新统计
            if result[:updated]
              if result[:success]
                stats[:updated] += 1
              else
                stats[:failed] += 1
                puts "❌ #{stock.symbol}: 刷新失败 - #{result[:error]}"
              end
            else
              stats[:skipped] += 1
            end

            # 每处理100条输出进度
            if stats[:updated] % 100 == 0 && stats[:updated] > 0
              puts "📈 已处理: #{stats[:updated] + stats[:skipped]}/#{stats[:total]} (更新: #{stats[:updated]}, 跳过: #{stats[:skipped]})"
            end
          rescue => e
            stats[:failed] += 1
            Rails.logger.error "StockRadarBatchService error for #{stock.symbol}: #{e.message}"
          end
        end

        # 输出最终统计
        puts "\n🎉 批量刷新完成！"
        puts "📊 统计结果:"
        puts "  - 总处理: #{stats[:total]} 条"
        puts "  - 更新: #{stats[:updated]} 条"
        puts "  - 跳过: #{stats[:skipped]} 条"
        puts "  - 失败: #{stats[:failed]} 条"

        stats
      end
    end
  end
end