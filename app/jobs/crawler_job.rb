class CrawlerJob < ApplicationJob
  queue_as :default

  def perform(task_name:, service_name:, method_name: "call", args: [], kwargs: {},
              single_mode: false, single_limit: nil, single_market: nil)
    start_time = Time.current

    begin
      service_class = service_name.constantize

      result = if single_mode
                 perform_single_mode(service_class, single_market, single_limit)
               elsif kwargs.present?
                 service_class.send(method_name, *args, **kwargs.symbolize_keys)
               elsif args.present?
                 service_class.send(method_name, *args)
               else
                 service_class.send(method_name)
               end

      message = build_message(task_name, result)
      duration = (Time.current - start_time).round(2)

      CrawlerExecution.create!(
        task_name: task_name, status: "success", message: message,
        duration: duration, executed_at: start_time
      )
    rescue => e
      duration = (Time.current - start_time).round(2)
      CrawlerExecution.create!(
        task_name: task_name, status: "error",
        message: "执行失败: #{e.message}", duration: duration, executed_at: start_time
      )
    end
  end

  private

  def perform_single_mode(service_class, market, limit)
    stats = { success: 0, failed: 0 }
    stocks = Stock.where(market: market).limit(limit)

    stocks.each do |stock|
      begin
        service_class.call_single(stock.symbol, market: market)
        stats[:success] += 1
      rescue => e
        Rails.logger.error "[CrawlerJob] #{stock.symbol}: #{e.message}"
        stats[:failed] += 1
      end
    end

    stats
  end

  def build_message(task_name, result)
    if result.is_a?(Hash)
      parts = []
      parts << "总计: #{result[:total]}" if result.key?(:total)
      parts << "成功: #{result[:success]}" if result.key?(:success)
      parts << "更新: #{result[:updated]}" if result.key?(:updated)
      parts << "失败: #{result[:failed]}" if result.key?(:failed)
      parts << "跳过: #{result[:skipped]}" if result.key?(:skipped)
      parts << "创建: #{result[:created]}" if result.key?(:created)
      parts << "API错误: #{result[:api_error]}" if result.key?(:api_error)
      return "#{task_name}完成 - #{parts.join(', ')}" if parts.any?
    end
    "#{task_name}完成"
  end
end