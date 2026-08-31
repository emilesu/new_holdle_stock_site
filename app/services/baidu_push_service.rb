# 百度搜索资源平台「主动推送」服务
#
# 设计约束（重要）：
# 1. 只推送「本次真实变更/新增」的 URL，绝不全量推送存量（会耗尽配额并降权）。
# 2. site / token 从环境变量读取；token 未配置时静默跳过，绝不抛异常影响主流程。
# 3. 同一 URL 不重复推送（baidu_push_urls 唯一索引）。
# 4. 单次最多 2000 条；超过当日剩余配额则只推配额内，多余记日志等待明天。
# 5. 超配额（over quota）时记录状态，当天剩余时间停止推送。
class BaiduPushService
  SITE = ENV["BAIDU_PUSH_SITE"].to_s.strip
  API_HOST = "data.zz.baidu.com".freeze
  BASE_URL = "https://www.holdle.com".freeze
  MAX_PER_REQUEST = 2000

  class << self
    # 入口：接收一批绝对 URL，过滤后推送。
    # @param urls [Array<String>]
    # @return [Hash] 统计结果；内部所有异常已 rescue，绝不 raise
    def push(urls)
      token = ENV["BAIDU_PUSH_TOKEN"].to_s.strip
      unless token.present?
        Rails.logger.warn "[BaiduPush] 未配置 BAIDU_PUSH_TOKEN，跳过推送 (batch=#{urls.size})"
        return { status: :skipped, reason: "no_token" }
      end

      # 先判是否已超配额（避免多余占位/外呼）
      return { status: :skipped, reason: "over_quota" } if over_quota_today?

      # 过滤出本站绝对 URL（去除 query/非法字符），并原子占位去重：
      # 通过 INSERT ... ON CONFLICT DO NOTHING 抢占，既保证同一 URL 只推一次，
      # 又避免并发下同一 URL 被多个 worker 重复 POST 到百度
      valid = valid_urls(urls)
      claimed = claim_urls(valid)
      if claimed.empty?
        Rails.logger.info "[BaiduPush] 无新增 URL 需要推送 (batch=#{urls.size}, valid=#{valid.size})"
        return { status: :skipped, reason: "all_dup" }
      end

      # 尊重当日剩余配额，且单批不超 2000
      quota = remaining_quota
      to_push = quota ? claimed.first([quota, MAX_PER_REQUEST].min) : claimed.first(MAX_PER_REQUEST)
      if to_push.size < claimed.size
        Rails.logger.warn "[BaiduPush] 本次应推=#{claimed.size}, 受配额限制仅推=#{to_push.size}, 其余留待明天"
        release_claimed(claimed - to_push)
      end

      result = send_batch(token, to_push)
      # 非成功路径（失败/超配额）：释放本次占位，允许日后重试
      release_claimed(to_push) unless result[:status] == :ok
      result
    rescue => e
      Rails.logger.error "[BaiduPush] 推送异常: #{e.class}: #{e.message}"
      { status: :error, reason: "exception" }
    end

    # 构造股票详情页绝对 URL（与 canonical 保持一致）
    def stock_url(stock)
      "#{BASE_URL}/stocks/#{stock.to_param}"
    end

    private

    def valid_urls(urls)
      Array(urls).flatten.map(&:to_s).uniq.select do |u|
        u.start_with?("#{BASE_URL}/") && u !~ /[\s?#&]/
      end
    end

    # 原子占位：INSERT ... ON CONFLICT DO NOTHING，返回本次成功占位的 URL
    #（已在库中/被并发 worker 抢占的 URL 会冲突跳过，从而既不重复推送也不重复外呼）
    def claim_urls(urls)
      now = Time.current
      claimed = []
      urls.each do |u|
        BaiduPushUrl.insert!({ url: u, pushed_at: now })
        claimed << u
      rescue ActiveRecord::RecordNotUnique
        next
      end
      claimed
    end

    # 释放占位（用于失败/无效/超配额未推送的 URL），允许日后重试
    def release_claimed(urls)
      return if urls.empty?
      BaiduPushUrl.where(url: urls).delete_all
    end

    def over_quota_today?
      state = BaiduPushState.singleton
      state.reset_if_new_day!
      state.over_quota
    end

    # 当天剩余配额；未知或尚未到新一天时默认不设限（用 MAX_PER_REQUEST 兜底）
    def remaining_quota
      state = BaiduPushState.singleton
      return nil if state.over_quota
      state.remain > 0 ? state.remain : nil
    end

    # 实际发送 HTTP 请求，解析百度响应
    def send_batch(token, urls)
      res = http_post_raw(token, urls)
      return handle_success(urls, parse_body(res)) if res.status == 200

      # 500 服务端偶发异常重试一次；重试同样走统一错误解析（含超配额熔断）
      if res.status >= 500
        res2 = http_post_raw(token, urls)
        return handle_success(urls, parse_body(res2)) if res2.status == 200
        return handle_failure(urls, res2, parse_body(res2))
      end

      handle_failure(urls, res, parse_body(res))
    end

    # 统一错误解析：识别超配额并熔断当日推送；否则记日志返回 error
    def handle_failure(urls, res, body)
      code_message = body.is_a?(Hash) ? (body["message"] || body["error"]) : body.to_s
      if code_message.to_s =~ /over\s*quota|配额/i
        mark_over_quota
        Rails.logger.error "[BaiduPush] 当日配额已用完(#{res.status}): #{code_message}，本批 #{urls.size} 条全部无效，暂停至次日"
        return { status: :over_quota }
      end
      Rails.logger.error "[BaiduPush] 推送失败(#{res.status}): #{code_message}"
      { status: :error, http_status: res.status, message: code_message }
    end

    def http_post_raw(token, urls)
      conn = Faraday.new(request: { timeout: 15, open_timeout: 10 })
      conn.post do |req|
        req.url "http://#{API_HOST}/urls", site: site_value, token: token
        req.headers["Content-Type"] = "text/plain"
        req.body = urls.join("\n")
      end
    end

    def site_value
      SITE.presence || "www.holdle.com"
    end

    def parse_body(res)
      JSON.parse(res.body)
    rescue JSON::ParserError
      res.body.to_s
    end

    def handle_success(urls, body)
      body = body.is_a?(Hash) ? body : {}
      success = body["success"]
      remain = body["remain"]
      rejected = Array(body["not_valid"]) + Array(body["not_same_site"])

      # 记录成功推送的 URL（排除不合法/非本站），并释放被拒绝 URL 的占位
      pushed_urls = urls - rejected
      release_claimed(rejected)
      record_pushed(pushed_urls)

      # 刷新当日剩余配额（百度成功响应应始终带 remain，缺失则保留原值）
      if body.key?("remain")
        state = BaiduPushState.singleton
        state.reset_if_new_day!
        state.update!(push_date: Date.current, remain: remain.to_i, over_quota: false)
      end

      Rails.logger.info "[BaiduPush] 推送成功 success=#{success || pushed_urls.size}, remain=#{remain}, 本次推 #{pushed_urls.size} 条"
      { status: :ok, pushed: pushed_urls.size, remain: remain }
    end

    def mark_over_quota
      state = BaiduPushState.singleton
      state.reset_if_new_day!
      state.update!(push_date: Date.current, over_quota: true)
    end

    # 写入已推送记录；并发下靠 url 唯一索引兜底
    def record_pushed(urls)
      now = Time.current
      urls.each do |u|
        BaiduPushUrl.find_or_create_by!(url: u) { |r| r.pushed_at = now }
      rescue ActiveRecord::RecordNotUnique
        next
      end
      urls.size
    end
  end
end