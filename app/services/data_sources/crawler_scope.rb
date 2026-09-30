module DataSources
  # 目标股票集合解析：把「任务定义 + 执行参数」翻译成待处理的股票 Relation
  #
  # 参数优先级（从具体到宽泛）：
  #   1. stock_ids   —— 后台勾选的具体股票（批量补抓）
  #   2. symbols     —— 按代码指定（命令行/调试用）
  #   3. stale_after —— 距上次成功同步超过 N 天的股票（定时增量、看板补抓）
  #   4. only_failed —— 最近一次同步失败的股票（失败重试）
  #   5. 兜底        —— 任务所属市场全量
  # 之后叠加断点过滤（after_stock_id）与数量上限（limit），统一按 id 升序。
  module CrawlerScope
    class << self
      def resolve(task:, params: {})
        params = (params || {}).symbolize_keys
        scope = base_scope(task, params)
        scope = apply_checkpoint(scope, params[:after_stock_id])
        scope = scope.limit(params[:limit].to_i) if params[:limit].present?
        scope.order(:id)
      end

      private

      def base_scope(task, params)
        return Stock.where(id: params[:stock_ids]) if params[:stock_ids].present?
        return Stock.where(symbol: params[:symbols]) if params[:symbols].present?

        if params[:stale_after].present? && task.sync_data_type.present?
          return stale_stocks(task, params[:stale_after].to_i.days)
        end

        return failed_stocks(task) if truthy?(params[:only_failed])

        market_scope(task)
      end

      # 「无同步记录」或「最后一次成功早于截止时间」的股票
      def stale_stocks(task, threshold)
        cutoff = Time.current - threshold
        succeeded_ids = StockDataSyncState
          .where(data_type: task.sync_data_type)
          .where.not(last_success_at: nil)
          .where(last_success_at: cutoff..)
          .select(:stock_id)

        market_scope(task).where.not(id: succeeded_ids)
      end

      def failed_stocks(task)
        failed_ids = StockDataSyncState
          .where(data_type: task.sync_data_type, status: "failed")
          .select(:stock_id)
        market_scope(task).where(id: failed_ids)
      end

      def market_scope(task)
        task.market.present? ? Stock.where(market: task.market) : Stock.all
      end

      def apply_checkpoint(scope, after_stock_id)
        return scope if after_stock_id.blank?

        scope.where("stocks.id > ?", after_stock_id.to_i)
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value).present?
      end
    end
  end
end
