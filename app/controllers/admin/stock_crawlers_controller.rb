module Admin
  class StockCrawlersController < ApplicationController
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
      execute_crawler("爬取美股名称&行业") do
        DataSources::UsStockBasicInfoService.call
        "美股名称&行业信息爬取完成"
      end
    end

    def us_finance
      execute_crawler("爬取美股全套财务") do
        DataSources::XueqiuUsFinanceService.call
        "美股全套财务数据爬取完成"
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
        DataSources::XueqiuAcnFinanceService.call
        "A股全套财务数据爬取完成"
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