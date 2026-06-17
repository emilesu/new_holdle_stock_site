module DataSources
  # 金字塔分数批量计算服务
  # 支持全量重算和增量更新两种模式
  class StockPyramidBatchService
    BATCH_SIZE = 100  # 分批处理大小，避免内存溢出

    class << self
      # 主入口方法
      # @param full_recalc [Boolean] true=全量重算所有股票，false=仅更新30天未计算的股票
      # @return [Hash] 统计结果 { total: Integer, updated: Integer, skipped: Integer, failed: Integer }
      def call(full_recalc: false)
        puts "🔄 开始#{full_recalc ? '全量' : '增量'}计算金字塔分数..."

        # 根据模式选择股票
        stocks = if full_recalc
          Stock.all
        else
          Stock.where(
            "last_pyramid_calc_at IS NULL OR last_pyramid_calc_at < ?",
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
            result = StockPyramidService.call(stock)
            
            # 更新统计
            if result[:updated]
              if result[:success]
                stats[:updated] += 1
                puts "✅ #{stock.symbol}: #{result[:old_score]} → #{result[:new_score]}"
              else
                stats[:failed] += 1
                puts "❌ #{stock.symbol}: 计算失败 - #{result[:error]}"
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
            Rails.logger.error "StockPyramidBatchService error for #{stock.symbol}: #{e.message}"
          end
        end

        # 输出最终统计
        puts "\n🎉 批量计算完成！"
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