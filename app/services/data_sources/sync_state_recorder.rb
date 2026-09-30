module DataSources
  # 股票数据同步状态的唯一写入入口（股票 × 数据类型）
  #
  # 集中在一处，保证「最近一次尝试」与「最近一次成功」的字段语义一致，
  # 也是后续统一接入其它抓取器的挂载点。
  # 写失败不影响爬取主流程。
  module SyncStateRecorder
    class << self
      def record(stock, data_type, ok:, error: nil)
        now = Time.current
        state = StockDataSyncState.find_or_initialize_by(stock_id: stock.id, data_type: data_type.to_s)
        state.market = stock.market
        state.last_attempt_at = now

        if ok
          state.status = "success"
          state.last_success_at = now
          state.retry_count = 0
          state.error_message = nil
        else
          state.status = "failed"
          state.retry_count = state.retry_count.to_i + 1
          state.error_message = truncate_error(error)
        end

        state.save!
        state
      rescue => e
        Rails.logger.error "[SyncStateRecorder] #{stock.symbol}/#{data_type} 状态写入失败: #{e.message}"
        nil
      end

      private

      def truncate_error(error)
        message = error.respond_to?(:message) ? error.message : error
        message.to_s.truncate(200)
      end
    end
  end
end
