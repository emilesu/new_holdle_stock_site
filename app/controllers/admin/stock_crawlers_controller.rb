module Admin
  # 爬虫管理首页：任务卡片（由注册表驱动）+ 最近执行记录
  class StockCrawlersController < BaseController
    # 首页只展示最近若干条，完整历史走「执行历史」页
    RECENT_LIMIT = 10

    def index
      @tasks_by_group = DataSources::CrawlerRegistry.by_group
      @last_executions = last_executions_by_task
      @crawler_active = CrawlerExecution.running.exists?
      @executions = CrawlerExecution.order(executed_at: :desc).limit(RECENT_LIMIT)
      @recent_total = CrawlerExecution.count
    end

    # 只接受注册表 key，不再接受任意类名/方法名，收窄后台可执行面
    def create
      task = DataSources::CrawlerRegistry.find(params[:task_key])
      unless task
        redirect_to admin_stock_crawlers_path, alert: "未知任务：#{params[:task_key]}"
        return
      end

      execution = DataSources::CrawlerExecutionStarter.call(
        task: task,
        trigger_source: "manual",
        params: crawl_params
      )
      redirect_to admin_stock_crawlers_path,
                  notice: "「#{task.name}」已提交后台执行（记录 ##{execution.id}），可在下方查看进度"
    end

    private

    # 手动触发时可携带的范围参数（测试用 limit、指定股票 stock_ids 等）
    def crawl_params
      params.permit(:limit, :stale_after, :only_failed, :after_stock_id, stock_ids: []).to_h
    end

    # 每个任务最近一次执行记录（PostgreSQL DISTINCT ON，避免把全部历史加载进内存）
    def last_executions_by_task
      CrawlerExecution
        .select("DISTINCT ON (task_key) *")
        .where(task_key: DataSources::CrawlerRegistry.keys)
        .order("task_key, executed_at DESC")
        .index_by(&:task_key)
    end
  end
end
