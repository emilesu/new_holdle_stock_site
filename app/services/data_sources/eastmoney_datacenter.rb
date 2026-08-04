module DataSources
  # 东方财富 datacenter 接口公共请求封装
  # 统一处理：URL、User-Agent/Referer、超时(15s)、失败重试2次(间隔1s)、result.data 解析
  # 失败语义由调用方决定：
  #   raise_on_failure: true  → 请求/解析失败抛异常，由调用方计入 failed 统计
  #   raise_on_failure: false → 失败记录日志并返回 nil，不阻断主流程（由其他服务兜底）
  module EastmoneyDatacenter
    BASE_URL = "https://datacenter.eastmoney.com/securities/api/data/v1/get".freeze
    REFERER = "https://emweb.securities.eastmoney.com/".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 15
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    module_function

    # 请求 datacenter 接口并返回 result.data 数组（无数据时返回空数组）
    # 参数：
    #   report_name: 报表名（如 RPT_F10_ORG_BASICINFO）
    #   columns: 查询字段（逗号分隔）
    #   filter: 过滤条件（东方财富 filter 语法）
    #   page_size: 每页条数
    #   http_client: 可插拔 HTTP 客户端（测试用），默认 Faraday
    #   raise_on_failure: 失败时是否抛异常（见模块注释）
    def fetch_data(report_name:, columns:, filter:, page_size:, http_client: nil, raise_on_failure: false)
      client = http_client || Faraday
      retries = RETRY_TIMES

      begin
        response = client.get(BASE_URL) do |req|
          req.headers["User-Agent"] = USER_AGENT
          req.headers["Referer"] = REFERER
          req.params.merge!({
            reportName: report_name,
            columns: columns,
            filter: filter,
            pageNumber: 1,
            pageSize: page_size,
            sortTypes: "",
            sortColumns: "",
            source: "F10",
            client: "PC"
          })
          req.options.timeout = TIMEOUT
        end

        unless response.success?
          message = "东方财富请求失败，状态码: #{response.status}"
          raise Faraday::Error, message if raise_on_failure
          Rails.logger.warn message
          return nil
        end

        JSON.parse(response.body).dig("result", "data") || []
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        retries -= 1
        if retries > 0
          Rails.logger.warn "东方财富请求超时/断连，重试中（剩余 #{retries} 次）..."
          sleep RETRY_INTERVAL
          retry
        end
        Rails.logger.error "东方财富请求失败（已重试 #{RETRY_TIMES} 次）: #{e.message}"
        raise if raise_on_failure
        nil
      rescue JSON::ParserError => e
        Rails.logger.error "东方财富JSON解析失败: #{e.message}"
        raise if raise_on_failure
        nil
      end
    end
  end
end
