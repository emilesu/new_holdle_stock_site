module Admin
  class StockCrawlersController < BaseController
    def index
      @results = CrawlerExecution.recent.to_a
    end

    def us_stock_list
      execute_crawler("爬取美股列表") do
        DataSources::NasdaqStockListService.call
        "美股列表爬取完成"
      end
    end

    def us_stock_basic
      UsStockBasicInfoJob.perform_later

      # 记录一个"执行中"的状态记录
      CrawlerExecution.create!(
        task_name: "爬取美股名称&行业",
        status: "running",
        message: "任务已提交，正在后台异步执行中...（请等待数小时完成）",
        duration: 0,
        executed_at: Time.current
      )

      redirect_to admin_stock_crawlers_path, notice: "爬取任务已提交后台异步执行，请稍后在执行结果中查看状态"
    end

    def us_finance
      execute_crawler("爬取美股全套财务") do
        result = DataSources::EastMoneyFinanceService.call(market: "US")
        "美股全套财务数据爬取完成(东方财富) - 成功: #{result[:success]}, 失败: #{result[:failed]}"
      end
    end

    def us_finance_em
      execute_crawler("爬取美股全套财务(东方财富)") do
        result = DataSources::EastMoneyFinanceService.call(market: "US")
        "美股全套财务数据爬取完成(东方财富) - 成功: #{result[:success]}, 失败: #{result[:failed]}"
      end
    end

    def us_finance_em_single
      limit = (params[:limit] || 5).to_i
      execute_crawler("爬取美股财务(东方财富) #{limit}只") do
        stocks = Stock.where(market: "US").limit(limit)
        stocks.each do |s|
          begin
            DataSources::EastMoneyFinanceService.call_single(s.symbol, market: "US")
          rescue => e
            Rails.logger.error "[us_finance_em_single] #{s.symbol}: #{e.message}"
          end
        end
        "#{limit}只美股财务数据爬取完成(东方财富)"
      end
    end

    def a_stock_list
      execute_crawler("爬取A股列表、名称&行业") do
        DataSources::AStockListService.call
        "A股列表及基本信息爬取完成"
      end
    end

    def a_finance
      execute_crawler("爬取A股全套财务") do
        result = DataSources::EastMoneyFinanceService.call(market: "CN")
        "A股全套财务数据爬取完成(东方财富) - 成功: #{result[:success]}, 失败: #{result[:failed]}"
      end
    end

    def a_finance_em
      execute_crawler("爬取A股全套财务(东方财富)") do
        result = DataSources::EastMoneyFinanceService.call(market: "CN")
        "A股全套财务数据爬取完成(东方财富) - 成功: #{result[:success]}, 失败: #{result[:failed]}"
      end
    end

    def a_finance_em_single
      limit = (params[:limit] || 5).to_i
      execute_crawler("爬取A股财务(东方财富) #{limit}只") do
        stocks = Stock.where(market: "CN").limit(limit)
        stocks.each do |s|
          begin
            DataSources::EastMoneyFinanceService.call_single(s.symbol, market: "CN")
          rescue => e
            Rails.logger.error "[a_finance_em_single] #{s.symbol}: #{e.message}"
          end
        end
        "#{limit}只A股财务数据爬取完成(东方财富)"
      end
    end

    def update_all_pyramid
      execute_crawler("全局更新金字塔分数") do
        stats = DataSources::StockPyramidBatchService.call(full_recalc: true)
        "金字塔分数更新完成 - 总计: #{stats[:total]}, 更新: #{stats[:updated]}, 跳过: #{stats[:skipped]}, 失败: #{stats[:failed]}"
      end
    end

    def refresh_all_radar
      execute_crawler("全局刷新雷达维度缓存") do
        stats = DataSources::StockRadarBatchService.call(full_recalc: false)
        "雷达维度缓存刷新完成 - 总计: #{stats[:total]}, 更新: #{stats[:updated]}, 跳过: #{stats[:skipped]}, 失败: #{stats[:failed]}"
      end
    end

    def hk_stock_list
      execute_crawler("爬取港股列表、名称&行业") do
        DataSources::HkStockListService.call
        "港股列表及基本信息爬取完成"
      end
    end

    def hk_finance
      execute_crawler("爬取港股全套财务") do
        result = DataSources::EastMoneyFinanceService.call(market: "HK")
        "港股全套财务数据爬取完成(东方财富) - 成功: #{result[:success]}, 失败: #{result[:failed]}"
      end
    end

    def hk_finance_em
      execute_crawler("爬取港股全套财务(东方财富)") do
        result = DataSources::EastMoneyFinanceService.call(market: "HK")
        "港股全套财务数据爬取完成(东方财富) - 成功: #{result[:success]}, 失败: #{result[:failed]}"
      end
    end

    def hk_finance_em_single
      limit = (params[:limit] || 5).to_i
      execute_crawler("爬取港股财务(东方财富) #{limit}只") do
        # 逐个爬取
        stocks = Stock.where(market: "HK").limit(limit)
        stocks.each do |s|
          begin
            DataSources::EastMoneyFinanceService.call_single(s.symbol, market: "HK")
          rescue => e
            Rails.logger.error "[hk_finance_em_single] #{s.symbol}: #{e.message}"
          end
        end
        "#{limit}只港股财务数据爬取完成(东方财富)"
      end
    end

    private

    def execute_crawler(task_name)
      start_time = Time.current
      begin
        result_message = yield
        duration = (Time.current - start_time).round(2)
        CrawlerExecution.create!(
          task_name: task_name,
          status: 'success',
          message: result_message,
          duration: duration,
          executed_at: start_time
        )
      rescue => e
        duration = (Time.current - start_time).round(2)
        CrawlerExecution.create!(
          task_name: task_name,
          status: 'error',
          message: "执行失败: #{e.message}",
          duration: duration,
          executed_at: start_time
        )
      end

      redirect_to admin_stock_crawlers_path
    end
  end
end
