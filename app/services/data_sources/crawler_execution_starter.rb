module DataSources
  # 执行记录创建 + 入队
  #
  # 后台按钮与定时任务共用，保证两条入口写出完全一致的字段口径（task_key 归一、
  # 参数白名单过滤、trigger_source 区分来源）。
  class CrawlerExecutionStarter
    # 允许落库的范围参数白名单（与 CrawlerScope 支持的参数对齐）
    SCOPE_KEYS = %i[stock_ids symbols stale_after only_failed after_stock_id limit].freeze

    class << self
      def call(task:, trigger_source:, params: {})
        params = normalize(params)
        execution = CrawlerExecution.create!(
          task_key: task.key,
          task_name: task.name,
          status: "running",
          message: "#{task.name}已入队，等待执行",
          duration: 0,
          executed_at: Time.current,
          trigger_source: trigger_source,
          market: task.market,
          params: params
        )
        CrawlerJob.perform_later(task_key: task.key, execution_id: execution.id, params: params)
        execution
      end

      private

      def normalize(params)
        params = (params || {}).symbolize_keys.slice(*SCOPE_KEYS)
        params[:stock_ids] = Array(params[:stock_ids]).map(&:to_i).uniq if params[:stock_ids].present?
        params[:symbols] = Array(params[:symbols]).map(&:to_s) if params[:symbols].present?
        %i[limit after_stock_id stale_after].each do |key|
          params[key] = params[key].to_i if params[key].present?
        end
        params.compact
      end
    end
  end
end
