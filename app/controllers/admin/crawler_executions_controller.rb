module Admin
  # 爬虫执行历史：列表 / 详情 / 从断点重试
  class CrawlerExecutionsController < BaseController
    PER_PAGE = 20

    def index
      @page = params[:page].presence&.to_i || 1
      @page = 1 if @page < 1
      @task_key = params[:task_key].presence
      @status = params[:status].presence
      @market = params[:market].presence

      scope = filtered_scope
      @total_count = scope.count
      @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
      @executions = scope.order(executed_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      @tasks = DataSources::CrawlerRegistry.all
    end

    def show
      @execution = CrawlerExecution.find(params[:id])
      @task = DataSources::CrawlerRegistry.find(@execution.task_key)
    end

    # 重试：新建一条执行记录并继承原参数；from_checkpoint 为真时从断点续跑
    def retry
      execution = CrawlerExecution.find(params[:id])
      task = DataSources::CrawlerRegistry.find(execution.task_key)
      unless task
        redirect_to admin_crawler_execution_path(execution), alert: "该任务已从注册表下线，无法重试"
        return
      end

      retry_params = (execution.params || {}).symbolize_keys
      # 续跑要求任务本身支持按股票子集执行，否则参数会被 CrawlerJob 丢弃、退化成全量重跑
      from_checkpoint = params[:from_checkpoint].present? &&
                        execution.resumable? &&
                        task.accepts_stock_scope?
      if from_checkpoint
        # 支持子集的服务均按 stock_ids ∩ after_stock_id 交集过滤，
        # 保留 stock_ids 让续跑仍限定在原股票子集内；
        # 删除它会把子集执行的续跑扩大为全市场重算
        retry_params[:after_stock_id] = execution.checkpoint["last_unit_id"]
      end

      new_execution = DataSources::CrawlerExecutionStarter.call(
        task: task,
        trigger_source: "retry",
        params: retry_params
      )
      hint = from_checkpoint ? "（已从断点 ##{execution.checkpoint['last_unit_id']} 续跑，跳过上次已处理到的股票）" : ""
      redirect_to admin_crawler_execution_path(new_execution),
                  notice: "「#{task.name}」已重新入队#{hint}，执行记录 ##{new_execution.id}"
    end

    private

    def filtered_scope
      scope = CrawlerExecution.all
      scope = scope.by_task(@task_key) if @task_key
      scope = scope.where(status: @status) if @status
      scope = scope.for_market(@market) if @market
      scope
    end
  end
end
