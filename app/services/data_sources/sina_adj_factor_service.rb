module DataSources
  # 新浪 A股复权因子抓取服务
  #
  # 因子文件形如：
  #   var sh600519qfq={"total":33,"data":[{"d":"2026-06-26", "f":"1.0000000000000000"},…]}
  #   data 按日期倒序返回，解析后统一按日期升序
  #
  # 因子语义（Task 0 探针已用真实复权价验证，详见设计方案 §2.4.1/§2.4.2）：
  #   后复权价 = 不复权价 × hfq_factor（以上市首日为基准归一，首日因子 = 1）
  #   前复权价 = 不复权价 ÷ qfq_factor（以最新日为基准归一，最新因子 = 1）
  #   两者关系：qfq_factor_i = hfq_last ÷ hfq_factor_i，故 后复权价 ÷ 前复权价 ≡ hfq_last（常数）
  #
  # 因子数组中含一条哨兵记录（日期 1900-01-01），用于覆盖「首次除权之前」的月份：
  #   hfq 哨兵因子 = 1（此时后复权价 = 不复权价），qfq 哨兵因子 = hfq_last，取用规则天然正确
  class SinaAdjFactorService
    BASE_URL = "https://finance.sina.com.cn/realstock/company".freeze
    REFERER = "https://finance.sina.com.cn/".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 15
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    # HTTP 非 2xx 响应（纳入重试范围）
    class RequestError < StandardError; end

    class << self
      # HTTP客户端，默认为Faraday，测试时可替换
      attr_writer :http_client

      def http_client
        @http_client || Faraday
      end

      # 前复权因子，返回 [{ date: Date, factor: BigDecimal }]，按日期升序
      def fetch_qfq(symbol)
        fetch_factors(symbol, "qfq")
      end

      # 后复权因子，返回 [{ date: Date, factor: BigDecimal }]，按日期升序
      def fetch_hfq(symbol)
        fetch_factors(symbol, "hfq")
      end

      # 库内 A股 symbol（如 SH600519）→ 新浪小写代码（sh600519）
      def sina_code(symbol)
        symbol.to_s.strip.downcase
      end

      private

      def fetch_factors(symbol, kind)
        code = sina_code(symbol)
        body = request("#{BASE_URL}/#{code}/#{kind}.js")
        factors = parse_factors(body)
        Rails.logger.warn "[SinaAdjFactor] #{code} #{kind} 因子为空" if factors.empty?
        factors
      rescue => e
        Rails.logger.error "[SinaAdjFactor] #{code} #{kind} 抓取失败：#{e.message}"
        []
      end

      def request(url)
        retries = RETRY_TIMES
        begin
          response = http_client.get(url) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = REFERER
            req.options.timeout = TIMEOUT
            req.options.open_timeout = TIMEOUT
          end

          raise RequestError, "HTTP #{response.status}" unless response.success?

          response.body
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed, RequestError => e
          # 首次请求 + RETRY_TIMES 次重试
          raise if retries.zero?

          retries -= 1
          Rails.logger.warn "[SinaAdjFactor] 请求异常，重试中（剩余 #{retries} 次）：#{e.message}"
          sleep RETRY_INTERVAL
          retry
        end
      end

      # 从 "var sh600519qfq={...}" 中截出 JSON 主体再解析
      def parse_factors(body)
        json_str = body.to_s[/=\s*(\{.*\})/m, 1]
        return [] if json_str.blank?

        data = JSON.parse(json_str)["data"]
        return [] unless data.is_a?(Array)

        data.filter_map { |item| build_factor(item) }.sort_by { |row| row[:date] }
      end

      def build_factor(item)
        date_str = item["d"].to_s
        factor_str = item["f"].to_s
        return nil if date_str.blank? || factor_str.blank?

        { date: Date.parse(date_str), factor: BigDecimal(factor_str) }
      rescue Date::Error, ArgumentError
        nil
      end
    end
  end
end