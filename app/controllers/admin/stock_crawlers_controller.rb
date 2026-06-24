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

    def update_all_pyramid
      execute_crawler("全局更新金字塔分数") do
        stats = DataSources::StockPyramidBatchService.call(full_recalc: false)
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
        DataSources::XueqiuHkFinanceService.call
        "港股全套财务数据爬取完成"
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
