module DataSources
  # 爬虫执行上下文：统一负责「进度上报 / 心跳 / 断点」
  #
  # 业务服务只需在批处理循环里调用：
  #   DataSources::CrawlContext.current&.tick(unit_id: stock.id, ok: true)
  # 不必关心写库频率与字段细节。
  #
  # 写库节流：tick 每只股票调用一次，若每只都 UPDATE 会显著拖慢爬取并放大 IO，
  # 故距上次写库不足 THROTTLE_SECONDS 时只更新内存计数，finish!/fail! 强制落库。
  #
  # 线程安全：生产环境 crawlers 队列只有 1 个 worker 线程（config/queue.yml），
  # 同一时刻只有一个爬虫任务，Thread.current 不会互相覆盖；with 内用 ensure 还原，
  # 防止线程复用导致的串号。
  # ⚠️ 若将来提高 crawlers 队列并发，必须改为「按执行 id 注册」的 context 表。
  class CrawlContext
    THROTTLE_SECONDS = 5
    # 断点与错误堆栈的保留长度，避免把异常信息写爆
    MAX_BACKTRACE_LINES = 20

    class << self
      def current
        Thread.current[:holdle_crawl_context]
      end

      def with(context)
        previous = Thread.current[:holdle_crawl_context]
        Thread.current[:holdle_crawl_context] = context
        yield
      ensure
        Thread.current[:holdle_crawl_context] = previous
      end
    end

    attr_reader :execution

    def initialize(execution:)
      @execution = execution
      @processed = 0
      @success = 0
      @failed = 0
      @checkpoint = {}
      @last_flushed_at = nil
    end

    def start!(total_count:)
      @execution.update_columns(
        status: "running",
        total_count: total_count.to_i,
        processed_count: 0,
        success_count: 0,
        failed_count: 0,
        heartbeat_at: Time.current,
        progress_message: "开始执行，共 #{total_count.to_i} 只"
      )
      flush!(force: true)
    end

    # 处理完一个单元（通常是一只股票）后调用
    def tick(unit_id: nil, ok: true, message: nil)
      @processed += 1
      ok ? @success += 1 : @failed += 1
      merge_checkpoint(last_unit_id: unit_id) if unit_id
      @message = message if message
      flush!
    end

    def checkpoint!(payload)
      merge_checkpoint(payload)
    end

    def finish!(message: nil)
      flush!(force: true)
      @execution.update_columns(
        status: "success",
        processed_count: @processed,
        success_count: @success,
        failed_count: @failed,
        progress_message: message || default_progress,
        message: message || @execution.message || "执行完成",
        heartbeat_at: Time.current,
        finished_at: Time.current,
        duration: duration_seconds
      )
    end

    def fail!(error)
      flush!(force: true)
      @execution.update_columns(
        status: "failed",
        processed_count: @processed,
        success_count: @success,
        failed_count: @failed,
        progress_message: "执行失败：#{error.message}",
        message: "执行失败: #{error.message}",
        error_detail: format_error(error),
        heartbeat_at: Time.current,
        finished_at: Time.current,
        duration: duration_seconds
      )
    end

    private

    def merge_checkpoint(payload)
      @checkpoint = @checkpoint.merge(payload.transform_keys(&:to_s))
    end

    def flush!(force: false)
      now = Time.current
      return if !force && @last_flushed_at && (now - @last_flushed_at) < THROTTLE_SECONDS

      @last_flushed_at = now
      @execution.update_columns(
        processed_count: @processed,
        success_count: @success,
        failed_count: @failed,
        checkpoint: @execution.checkpoint.to_h.merge(@checkpoint),
        heartbeat_at: now,
        progress_message: default_progress
      )
    rescue => e
      # 进度上报绝不允许影响爬取主流程
      Rails.logger.error "[CrawlContext] 进度写入失败(execution=#{@execution.id}): #{e.message}"
    end

    def default_progress
      @message || "已处理 #{@processed}/#{@execution.total_count.to_i}，成功 #{@success}，失败 #{@failed}"
    end

    def duration_seconds
      return @execution.duration.to_f if @execution.executed_at.blank?

      (Time.current - @execution.executed_at).round(2)
    end

    def format_error(error)
      lines = [ "#{error.class}: #{error.message}" ]
      lines.concat(Array(error.backtrace).first(MAX_BACKTRACE_LINES))
      lines.join("\n")
    end
  end
end
