module DataSources
  # 金字塔分数批量计算服务
  # 支持全量重算、增量更新和按股票子集执行（后台「指定股票」入口）三种模式
  class StockPyramidBatchService
    BATCH_SIZE = 100  # 分批处理大小，避免内存溢出

    class << self
      # 主入口方法
      # @param full_recalc [Boolean] true=全量重算所有股票，false=仅更新30天未计算的股票（传了 stock_ids 时忽略）
      # @param stock_ids [Array<Integer>, nil] 按股票子集执行（后台指定股票补算）
      # @param after_stock_id [Integer, nil] 断点续跑：只处理 id 大于该值的股票
      # @param limit [Integer, nil] 数量上限（后台「测试 5 只」）
      # @return [Hash] 统计结果 { total: Integer, updated: Integer, skipped: Integer, failed: Integer }
      def call(full_recalc: false, stock_ids: nil, after_stock_id: nil, limit: nil)
        # 子集优先：指定股票时只算这批，full_recalc 语义退让
        stocks = if stock_ids.present?
          Stock.where(id: stock_ids)
        elsif full_recalc
          Stock.all
        else
          Stock.where(
            "last_pyramid_calc_at IS NULL OR last_pyramid_calc_at < ?",
            30.days.ago
          )
        end
        stocks = stocks.where("stocks.id > ?", after_stock_id.to_i) if after_stock_id.present?
        stocks = stocks.limit(limit.to_i) if limit.present?
        stocks = stocks.order(:id)

        mode_label = stock_ids.present? ? "指定 #{stock_ids.size} 只" : (full_recalc ? "全量" : "增量")
        puts "🔄 开始#{mode_label}计算金字塔分数..."

        # 初始化统计数据
        stats = {
          total: stocks.count,
          updated: 0,
          skipped: 0,
          failed: 0
        }
        # 自报目标数量，纠正 CrawlerJob 进度分母
        CrawlContext.current&.start!(total_count: stats[:total])

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
            CrawlContext.current&.tick(unit_id: stock.id, ok: result[:success])

            # 每处理100条输出进度
            if stats[:updated] % 100 == 0 && stats[:updated] > 0
              puts "📈 已处理: #{stats[:updated] + stats[:skipped]}/#{stats[:total]} (更新: #{stats[:updated]}, 跳过: #{stats[:skipped]})"
            end
          rescue => e
            stats[:failed] += 1
            CrawlContext.current&.tick(unit_id: stock.id, ok: false)
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