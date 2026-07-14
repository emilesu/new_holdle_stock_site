# 爬虫基础父类，封装通用HTTP请求、重试、请求头、数据清洗、异常处理
class BaseSpiderService
  # 从环境变量读取配置（已停用雪球，设默认值避免加载崩溃）
  USER_AGENT = ENV.fetch("XUEQIU_USER_AGENT", "")
  REFERER = ENV.fetch("XUEQIU_REFERER", "")
  COOKIE = ENV.fetch("XUEQIU_COOKIE", "")
  TIMEOUT = ENV.fetch("SPIDER_TIMEOUT", 30).to_i
  RETRY_TIMES = ENV.fetch("SPIDER_RETRY_TIMES", 2).to_i

  def initialize
    # Faraday 2.x 最稳妥的超时配置方式：直接在 new 里传参数
    @conn = Faraday.new(
      url: ENV["XUEQIU_BASE_URL"],
      request: {
        timeout: TIMEOUT,
        open_timeout: TIMEOUT
      }
    ) do |f|
      f.adapter Faraday.default_adapter
    end
  end

  # 通用GET请求方法，自带重试机制
  def get(path, params = {})
    retries = 0
    begin
      response = @conn.get(path, params) do |req|
        req.headers["User-Agent"] = USER_AGENT
        req.headers["Referer"] = REFERER
        req.headers["Cookie"] = COOKIE
        req.headers["Accept"] = "application/json"
      end

      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.warn("接口请求失败，状态码：#{response.status}，请求路径：#{path}")
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      retries += 1
      if retries <= RETRY_TIMES
        sleep 1
        retry
      else
        Rails.logger.error("请求超时/连接失败（已重试#{RETRY_TIMES}次）：#{e.message}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("请求发生未知异常：#{e.message}")
      nil
    end
  end

  # 通用数据清洗：处理雪球特殊空值、数组格式，保证财务数据精度
  def clean_value(val)
    return nil if val.nil?

    # 雪球部分字段会用数组包裹真实值，取数组第一个元素
    val = val.first if val.is_a?(Array) && val.present?

    str_val = val.to_s.strip
    # 过滤雪球常见无效值
    return nil if str_val.in?(["", "--", "null", " -- "])

    # 转为高精度十进制，避免财务数据浮点精度丢失
    BigDecimal(str_val) rescue nil
  end
end