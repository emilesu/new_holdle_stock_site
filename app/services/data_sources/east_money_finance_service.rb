module DataSources
  # 统一财务数据爬取编排器（东方财富数据源）
  # 替代现有的三个雪球编排器（XueqiuAcnFinanceService / XueqiuHkFinanceService / XueqiuUsFinanceService）
  #
  # 使用方式：
  #   DataSources::EastMoneyFinanceService.call(limit: 30, market: "HK")
  #   DataSources::EastMoneyFinanceService.call(limit: 10, market: "CN")
  #   DataSources::EastMoneyFinanceService.call(market: "US")
  class EastMoneyFinanceService
    FETCHER_MAP = {
      "CN" => DataSources::Fetchers::CnFetcher,
      "HK" => DataSources::Fetchers::HkFetcher,
      "US" => DataSources::Fetchers::UsFetcher,
    }.freeze

    MARKET_NAMES = {
      "CN" => "A股",
      "HK" => "港股",
      "US" => "美股",
    }.freeze

    LISTED_STATUS = "listed".freeze

    class << self
      def call(limit: nil, market: "CN")
        market_name = MARKET_NAMES[market] || market
        puts "\n#{'=' * 70}"
        puts "🚀 开始执行#{market_name}财务数据爬取任务 (东方财富数据源)"
        puts "#{'=' * 70}"

        fetcher_class = FETCHER_MAP[market]
        unless fetcher_class
          puts "❌ 不支持的市场: #{market}"
          return
        end

        fetcher = fetcher_class.new
        stocks = Stock.where(market: market)
        total_count = stocks.count
        stocks = stocks.limit(limit) if limit
        batch_size = stocks.count

        puts "\n📋 待爬取股票共 #{total_count} 只, 本次爬取 #{batch_size} 只"

        success_count = 0
        fail_count = 0
        changed_symbols = []

        stocks.each_with_index do |stock, index|
          puts "\n--- [#{index + 1}/#{batch_size}] #{stock.symbol} | #{stock.name} ---"

          begin
            result = fetcher.fetch_all(stock)
            all_success = result.is_a?(Hash) ? result[:success] : result
            if all_success
              update_stock_status(stock)
              success_count += 1
              # 严格按「报表真实新建/更新」判定，作为百度推送数据源
              changed_symbols << stock.symbol if result.is_a?(Hash) && result[:changed]
              puts "  ✅ [#{stock.symbol}] 全部报表爬取成功"
            else
              fail_count += 1
              puts "  ⚠️  [#{stock.symbol}] 部分报表爬取失败"
            end
          rescue => e
            fail_count += 1
            puts "  ❌ [#{stock.symbol}] 处理异常: #{e.message}"
            Rails.logger.error "[EastMoneyFinanceService] #{stock.symbol} 处理异常: #{e.message}"
          end
        end

        # 财务数据真实变更的股票 → 异步推送百度（附加动作，失败不影响主流程）
        push_changed_to_baidu(changed_symbols, market)

        puts "\n#{'=' * 70}"
        puts "📊 #{market_name}财务数据爬取任务完成"
        puts "   成功: #{success_count} 只, 失败: #{fail_count} 只"
        puts "#{'=' * 70}"

        { success: success_count, failed: fail_count }
      end

      def call_single(symbol, market: "CN")
        market_name = MARKET_NAMES[market] || market
        puts "\n#{'=' * 70}"
        puts "🚀 单只#{market_name}股票财务数据爬取: #{symbol}"
        puts "#{'=' * 70}"

        # 尝试多种代码格式查找股票
        stock = find_stock(symbol, market)
        unless stock
          puts "❌ 未找到股票: #{symbol} (#{market})"
          return { status: :error, error: "股票不存在" }
        end

        fetcher_class = FETCHER_MAP[market]
        unless fetcher_class
          puts "❌ 不支持的市场: #{market}"
          return { status: :error, error: "不支持的市场" }
        end

        fetcher = fetcher_class.new
        fetch_result = fetcher.fetch_all(stock)
        all_success = fetch_result.is_a?(Hash) ? fetch_result[:success] : fetch_result
        update_stock_status(stock) if all_success

        # 单只财务数据真实变更 → 推送百度（附加动作，失败不影响主流程）
        if fetch_result.is_a?(Hash) && fetch_result[:changed]
          begin
            BaiduPushJob.perform_later([BaiduPushService.stock_url(stock)])
          rescue => e
            Rails.logger.error "[EastMoneyFinanceService] #{stock.symbol} 百度推送入队失败: #{e.message}"
          end
        end

        { status: all_success ? :success : :partial, error: nil }
      end

      private

      # 收集本次真实变更的股票 URL，异步推送百度；失败仅记日志，绝不中断主流程
      def push_changed_to_baidu(symbols, _market)
        return if symbols.empty?
        stocks = Stock.where(symbol: symbols).index_by(&:symbol)
        urls = symbols.filter_map { |sym| stocks[sym] && BaiduPushService.stock_url(stocks[sym]) }
        return if urls.empty?
        BaiduPushJob.perform_later(urls)
      rescue => e
        Rails.logger.error "[EastMoneyFinanceService] 百度推送入队失败: #{e.message}"
      end

      # 尝试多种代码格式查找股票
      def find_stock(symbol, market)
        stock = Stock.find_by(symbol: symbol, market: market)
        return stock if stock

        # 尝试移除市场后缀（如 00700.HK → 00700）
        clean_symbol = symbol.sub(/\.\w+$/, "")
        if clean_symbol != symbol
          stock = Stock.find_by(symbol: clean_symbol, market: market)
          return stock if stock
        end

        # 尝试添加 .HK 后缀（港股，如 00700 → 00700.HK）
        if market == "HK" && !symbol.end_with?(".HK")
          stock = Stock.find_by(symbol: "#{symbol}.HK", market: market)
          return stock if stock
        end

        nil
      end

      def update_stock_status(stock)
        current_status = stock.status.to_s.strip
        if current_status == LISTED_STATUS
          puts "  ⏭️ 股票状态已是 #{LISTED_STATUS}，无需更新"
          return
        end

        puts "  📝 更新股票状态: '#{current_status.presence || '空'}' -> '#{LISTED_STATUS}'"
        stock.update!(status: LISTED_STATUS)
        puts "  ✅ 股票状态更新成功"
      rescue => e
        puts "  ❌ 更新股票状态失败: #{e.message}"
      end
    end
  end
end