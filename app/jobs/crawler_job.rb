# 爬虫长任务执行器
#
# 长任务（财务/列表爬取，单次可能跑数小时）独立队列，由 config/queue.yml 中专用 worker
# 串行消费，避免占满 default 队列线程导致定时任务积压。
#
# 设计要点：
#   1. 只接受注册表 key（DataSources::CrawlerRegistry），不再接受任意类名字符串，
#      收窄后台可执行面。
#   2. 进度/心跳/断点统一交给 DataSources::CrawlContext，业务服务无需关心写库细节。
#   3. 不做整任务自动重试：数小时的任务自动重试会在低配服务器上叠加不可控负载，
#      改为「失败可观测 + 后台一键从断点续跑」。
class CrawlerJob < ApplicationJob
  queue_as :crawlers

  # 可透传给业务服务的股票范围参数（由服务方法签名决定实际接受哪些）
  SCOPE_PARAM_KEYS = %i[stock_ids after_stock_id limit].freeze

  RESULT_LABELS = {
    total: "总计", success: "成功", updated: "更新", created: "创建",
    failed: "失败", skipped: "跳过", bars: "月K", inserted: "新增行", api_error: "API错误"
  }.freeze

  def perform(task_key:, execution_id:, params: {})
    task = DataSources::CrawlerRegistry.find(task_key)
    execution = CrawlerExecution.find(execution_id)

    unless task
      execution.update_columns(
        status: "failed",
        message: "未知任务 key: #{task_key}",
        error_detail: "DataSources::CrawlerRegistry 中不存在 key=#{task_key}",
        finished_at: Time.current
      )
      return
    end

    context = DataSources::CrawlContext.new(execution: execution)
    params = (params || {}).symbolize_keys

    DataSources::CrawlContext.with(context) do
      begin
        scope = DataSources::CrawlerScope.resolve(task: task, params: params)
        context.start!(total_count: scope.count)

        result = call_service(task, params)
        context.finish!(message: finish_message(task, result))
      rescue => e
        Rails.logger.error "[CrawlerJob] #{task.key} 执行失败: #{e.class}: #{e.message}"
        context.fail!(e)
      end
    end
  end

  private

  def call_service(task, params)
    kwargs = (task.kwargs || {}).transform_keys(&:to_sym).dup
    kwargs.merge!(scoped_kwargs(task, params))
    task.service_class.public_send(task.method_name, **kwargs)
  end

  # 只透传业务方法签名里真实声明了的关键字参数，避免给不支持股票范围的
  # 服务（如 NasdaqStockListService#call）传参导致 ArgumentError
  def scoped_kwargs(task, params)
    return {} unless task.accepts_stock_scope?

    accepted = task.service_class.method(task.method_name)
      .parameters.select { |type, _name| %i[key keyreq].include?(type) }
      .map(&:last)

    SCOPE_PARAM_KEYS.each_with_object({}) do |key, result|
      result[key] = params[key] if params.key?(key) && accepted.include?(key)
    end
  end

  def finish_message(task, result)
    return "#{task.name}完成" unless result.is_a?(Hash)

    parts = RESULT_LABELS.filter_map do |key, label|
      "#{label}: #{result[key]}" if result.key?(key)
    end
    parts.any? ? "#{task.name}完成 - #{parts.join(', ')}" : "#{task.name}完成"
  end
end
