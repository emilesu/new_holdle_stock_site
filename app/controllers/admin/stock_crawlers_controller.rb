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

      symbols = parse_symbols(params[:symbols])
      scope_params = crawl_params
      unmatched_count = 0

      if symbols.any?
        unless task.accepts_stock_scope?
          redirect_to admin_stock_crawlers_path, alert: "「#{task.name}」不支持按指定股票执行"
          return
        end

        # 代码 → stock_ids：解析结果即执行范围，避免 symbols 与 stock_ids 双口径
        matched_ids = Stock.where(symbol: symbols).pluck(:id)
        # 与看板批量补抓同款防护：指定了代码但一只都没匹配时绝不退化为全量执行
        if matched_ids.empty?
          redirect_to admin_stock_crawlers_path,
                      alert: "未匹配到任何股票：#{symbols.first(5).join(', ')}#{'…' if symbols.size > 5}"
          return
        end

        unmatched_count = symbols.size - matched_ids.size
        scope_params = scope_params.merge(stock_ids: matched_ids)
      end

      execution = DataSources::CrawlerExecutionStarter.call(
        task: task,
        trigger_source: "manual",
        params: scope_params
      )
      notice = "「#{task.name}」已提交后台执行（记录 ##{execution.id}），可在下方查看进度"
      notice += "（#{unmatched_count} 个代码未匹配，已忽略）" if unmatched_count > 0
      redirect_to admin_stock_crawlers_path, notice: notice
    end

    private

    # 「指定股票」输入框：逗号/分号/空白分隔的代码列表
    def parse_symbols(raw)
      raw.to_s.split(/[,，;；\s]+/).map(&:strip).reject(&:blank?).uniq
    end

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
