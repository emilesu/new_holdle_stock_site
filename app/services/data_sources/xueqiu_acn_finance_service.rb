module DataSources
  class XueqiuAcnFinanceService
    LISTED_STATUS = "listed".freeze
    PENDING_STATUS = "pending".freeze

    class << self
      def call
        puts "=" * 70
        puts "开始执行A股财务数据爬取任务"
        puts "=" * 70

        pending_stocks = Stock.where(market: "CN")
        puts "\n待爬取股票数量: #{pending_stocks.count}"

        success_count = 0
        fail_count = 0

        pending_stocks.each do |stock|
          puts "\n" + "-" * 70
          puts "处理股票: #{stock.symbol} | #{stock.name}"
          puts "-" * 70

          begin
            success = call_single(stock.symbol)
            if success
              update_stock_status(stock)
              success_count += 1
            else
              fail_count += 1
              puts "⚠️ #{stock.symbol} 部分表爬取失败"
            end
          rescue => e
            fail_count += 1
            puts "❌ #{stock.symbol} 处理失败: #{e.message}"
          end
        end

        puts "\n" + "=" * 70
        puts "A股财务数据爬取任务完成"
        puts "📊 统计结果: 成功 #{success_count} 只, 失败 #{fail_count} 只"
        puts "=" * 70
      end

      def call_single(symbol)
        puts "\n" + "-" * 70
        puts "单只A股股票财务数据爬取"
        puts "股票代码: #{symbol}"
        puts "-" * 70

        results = []
        
        results << { name: "利润表", result: execute_service("利润表") { XueqiuIncomeStatementService.call(symbol, market: "CN") } }
        results << { name: "资产负债表", result: execute_service("资产负债表") { XueqiuBalanceSheetService.call(symbol, market: "CN") } }
        results << { name: "现金流量表", result: execute_service("现金流量表") { XueqiuCashFlowService.call(symbol, market: "CN") } }
        results << { name: "财务指标", result: execute_service("财务指标") { XueqiuIndicatorService.call(symbol, market: "CN") } }

        puts "\n" + "=" * 70
        puts "#{symbol} 财务数据爬取汇总"
        puts "=" * 70
        
        success_count = results.count { |r| r[:result] == :success }
        fail_count = results.count { |r| r[:result] == :failed }
        
        results.each do |r|
          status = r[:result] == :success ? "✅" : "❌"
          puts "#{status} #{r[:name]}: #{r[:result] == :success ? '成功' : '失败'}"
        end
        
        puts "\n📊 单只股票统计: 成功 #{success_count} 表, 失败 #{fail_count} 表"
        puts "=" * 70

        fail_count == 0
      end

      private

      def execute_service(name, &block)
        puts "\n🔄 开始爬取 #{name}..."
        begin
          block.call
          :success
        rescue => e
          puts "❌ #{name}爬取失败: #{e.message}"
          :failed
        end
      end

      def update_stock_status(stock)
        current_status = stock.status.to_s.strip
        if current_status == LISTED_STATUS
          puts "⏭️ 股票状态已是 #{LISTED_STATUS}，无需更新"
          return
        end

        puts "📝 更新股票状态: '#{current_status.presence || '空'}' -> '#{LISTED_STATUS}'"
        stock.update!(status: LISTED_STATUS)
        puts "✅ 股票状态更新成功"
      rescue => e
        puts "❌ 更新股票状态失败: #{e.message}"
      end
    end
  end
end