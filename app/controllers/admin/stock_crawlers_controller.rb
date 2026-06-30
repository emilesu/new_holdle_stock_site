module Admin
  class StockCrawlersController < BaseController
    def index
      @results = CrawlerExecution.recent.to_a
    end

    # ──────────────────────────────────────────────
    # 美股爬虫
    # ──────────────────────────────────────────────

    def us_stock_list
      enqueue_crawler("爬取美股列表", "DataSources::NasdaqStockListService")
    end

    def us_stock_basic
      enqueue_crawler("爬取美股名称&行业", "DataSources::UsStockBasicInfoService")
    end

    def us_finance
      enqueue_crawler("爬取美股全套财务", "DataSources::EastMoneyFinanceService", kwargs: { market: "US" })
    end

    def us_finance_em
      enqueue_crawler("爬取美股全套财务(东方财富)", "DataSources::EastMoneyFinanceService", kwargs: { market: "US" })
    end

    def us_finance_em_single
      limit = (params[:limit] || 5).to_i
      enqueue_crawler("爬取美股财务(东方财富) #{limit}只", "DataSources::EastMoneyFinanceService",
                      single_mode: true, single_limit: limit, single_market: "US")
    end

    # ──────────────────────────────────────────────
    # A股爬虫
    # ──────────────────────────────────────────────

    def a_stock_list
      enqueue_crawler("爬取A股列表、名称&行业", "DataSources::AStockListService")
    end

    def a_finance
      enqueue_crawler("爬取A股全套财务", "DataSources::EastMoneyFinanceService", kwargs: { market: "CN" })
    end

    def a_finance_em
      enqueue_crawler("爬取A股全套财务(东方财富)", "DataSources::EastMoneyFinanceService", kwargs: { market: "CN" })
    end

    def a_finance_em_single
      limit = (params[:limit] || 5).to_i
      enqueue_crawler("爬取A股财务(东方财富) #{limit}只", "DataSources::EastMoneyFinanceService",
                      single_mode: true, single_limit: limit, single_market: "CN")
    end

    # ──────────────────────────────────────────────
    # 港股爬虫
    # ──────────────────────────────────────────────

    def hk_stock_list
      enqueue_crawler("爬取港股列表、名称&行业", "DataSources::HkStockListService")
    end

    def hk_finance
      enqueue_crawler("爬取港股全套财务", "DataSources::EastMoneyFinanceService", kwargs: { market: "HK" })
    end

    def hk_finance_em
      enqueue_crawler("爬取港股全套财务(东方财富)", "DataSources::EastMoneyFinanceService", kwargs: { market: "HK" })
    end

    def hk_finance_em_single
      limit = (params[:limit] || 5).to_i
      enqueue_crawler("爬取港股财务(东方财富) #{limit}只", "DataSources::EastMoneyFinanceService",
                      single_mode: true, single_limit: limit, single_market: "HK")
    end

    # ──────────────────────────────────────────────
    # 数据计算
    # ──────────────────────────────────────────────

    def update_all_pyramid
      enqueue_crawler("全局更新金字塔分数", "DataSources::StockPyramidBatchService", kwargs: { full_recalc: true })
    end

    def refresh_all_radar
      enqueue_crawler("全局刷新雷达维度缓存(增量)", "DataSources::StockRadarBatchService", kwargs: { full_recalc: false })
    end

    def refresh_all_radar_full
      enqueue_crawler("全局刷新雷达维度缓存(全量)", "DataSources::StockRadarBatchService", kwargs: { full_recalc: true })
    end

    private

    def enqueue_crawler(task_name, service_name, method_name: "call", args: [],
                        kwargs: {}, single_mode: false, single_limit: nil, single_market: nil)
      CrawlerJob.perform_later(
        task_name: task_name,
        service_name: service_name,
        method_name: method_name,
        args: args,
        kwargs: kwargs,
        single_mode: single_mode,
        single_limit: single_limit,
        single_market: single_market
      )

      CrawlerExecution.create!(
        task_name: task_name,
        status: "running",
        message: "任务已提交，正在后台异步执行中...",
        duration: 0,
        executed_at: Time.current
      )

      redirect_to admin_stock_crawlers_path, notice: "爬取任务已提交后台异步执行，请稍后在执行结果中查看状态"
    end
  end
end