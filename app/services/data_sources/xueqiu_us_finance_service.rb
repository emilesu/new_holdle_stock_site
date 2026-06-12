module DataSources
  class XueqiuUsFinanceService
    class << self
      def call
        puts "=" * 70
        puts "开始执行美股财务数据爬取任务"
        puts "=" * 70

        pending_stocks = Stock.where(market: "US", status: "listed")
        puts "\n待爬取股票数量: #{pending_stocks.count}"

        success_count = 0
        fail_count = 0

        pending_stocks.each do |stock|
          puts "\n" + "-" * 70
          puts "处理股票: #{stock.symbol} | #{stock.name}"
          puts "-" * 70

          begin
            XueqiuIncomeStatementService.call(stock.symbol, market: "US")
            success_count += 1
          rescue => e
            fail_count += 1
            puts "❌ #{stock.symbol} 处理失败: #{e.message}"
          end
        end

        puts "\n" + "=" * 70
        puts "美股财务数据爬取任务完成"
        puts "📊 统计结果: 成功 #{success_count} 只, 失败 #{fail_count} 只"
        puts "=" * 70
      end

      def call_single(symbol)
        puts "\n" + "-" * 70
        puts "单只股票财务数据爬取"
        puts "-" * 70

        XueqiuIncomeStatementService.call(symbol, market: "US")
      end
    end
  end
end