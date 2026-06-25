module DataSources
  module Fetchers
    # 东方财富财务数据抓取器基类
    # 封装通用逻辑：HTTP客户端、重试、日期解析、FinancialReport 匹配
    class BaseFetcher
      BASE_URL = "https://datacenter.eastmoney.com/securities/api/data/v1/get".freeze
      TIMEOUT = 15
      RETRY_MAX = 3
      RETRY_DELAY = 2
      MAX_YEARS_BACK = 10

      EASTMONEY_HEADERS = {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer" => "https://emweb.securities.eastmoney.com/",
        "Accept" => "application/json",
        "Accept-Language" => "zh-CN,zh;q=0.9"
      }.freeze

      # 获取所有四张报表
      def fetch_all(stock)
        raise NotImplementedError, "子类必须实现 #{__method__}"
      end

      private

      # 通用 HTTP GET 请求（含重试）
      def http_get(url, params: {}, headers: {})
        retries = 0
        begin
          conn = Faraday.new(request: { timeout: TIMEOUT, open_timeout: TIMEOUT })
          response = conn.get(url, params, EASTMONEY_HEADERS.merge(headers))
          return JSON.parse(response.body) if response.success?
          Rails.logger.warn "[#{self.class}] HTTP #{response.status}: #{url}"
          nil
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries += 1
          if retries <= RETRY_MAX
            Rails.logger.warn "[#{self.class}] 请求超时/失败(#{retries}/#{RETRY_MAX}): #{e.message}"
            sleep RETRY_DELAY
            retry
          else
            Rails.logger.error "[#{self.class}] 重试 #{RETRY_MAX} 次后仍失败: #{e.message}"
            nil
          end
        rescue => e
          Rails.logger.error "[#{self.class}] 请求异常: #{e.message}"
          nil
        end
      end

      # 获取或创建 FinancialReport 主记录
      def find_or_create_financial_report(stock, report_date:, report_type:, market:)
        financial_report = FinancialReport.find_or_initialize_by(
          stock_id: stock.id,
          report_date: report_date,
          report_type: report_type,
          market: market
        )
        financial_report.market = market
        financial_report.save!
        financial_report
      end

      # 解析 BigDecimal（直接数值，四舍五入到2位小数）
      def parse_decimal(value)
        return nil if value.nil? || value.to_s.strip.empty? || value.to_s.downcase == "null"
        BigDecimal(value.to_s).round(2)
      rescue ArgumentError
        nil
      end

      # 数据变更检测
      def data_changed?(record, new_data)
        new_data.each do |key, value|
          return true if record.send(key) != value
        end
        false
      end

      # 动态更新记录字段
      def update_record(record, new_data)
        new_data.each do |key, value|
          record.send("#{key}=", value)
        end
        record.save!
      end

      # 标记爬取完成时间
      def mark_crawled(financial_report)
        financial_report.update!(last_crawled_at: Time.current)
      end

      # 增加重试计数
      def increment_retry(financial_report)
        financial_report&.update(retry_count: (financial_report.retry_count || 0) + 1)
      end

      # 判断是否为近10年年报
      def keep_annual_report_date?(report_date_str)
        return false unless report_date_str.present?
        begin
          date = Date.parse(report_date_str)
          # 仅保留年报（12月31日）
          return false unless date.month == 12 && date.day == 31
          # 仅保留近10年
          date >= MAX_YEARS_BACK.years.ago.to_date
        rescue
          false
        end
      end

      # 打印进度
      def log_progress(stock, statement_name, status, detail = nil)
        icon = case status
               when :success then "✅"
               when :skipped then "⏭️"
               when :failed then "❌"
               else "🔄"
               end
        msg = "#{icon} [#{stock.symbol}] #{statement_name}: #{status}"
        msg += " | #{detail}" if detail
        puts msg
        Rails.logger.info "[EastMoney] #{msg}"
      end

      # 从东财 API 返回中提取数据列表
      def extract_data_list(response)
        return [] unless response.is_a?(Hash)
        data = response.dig("result", "data")
        data.is_a?(Array) ? data : []
      end

      # 统一保存逻辑：检测存在/变更，新建或更新
      # 使用 (stock_id, report_date, market) 唯一约束进行查找，避免重复插入
      # 子类必须定义 REPORT_TYPE_CODE 常量
      def save_model_record(stock, financial_report, model_class, report_date, market, financial_data)
        report_type = financial_data.delete(:report_type) || self.class::REPORT_TYPE_CODE

        record = model_class.find_or_initialize_by(
          stock_id: stock.id,
          report_date: report_date,
          market: market
        )

        if record.new_record?
          record.assign_attributes(
            financial_report_id: financial_report.id,
            report_type: report_type
          )
          financial_data.each { |k, v| record.send("#{k}=", v) }
          save_with_overflow_protection(record, financial_data)
          mark_crawled(financial_report)
          :success
        else
          new_data = financial_data.merge(report_type: report_type)

          if data_changed?(record, new_data)
            record.financial_report_id = financial_report.id
            new_data.each { |k, v| record.send("#{k}=", v) if financial_data.key?(k) }
            save_with_overflow_protection(record, financial_data)
            mark_crawled(financial_report)
            :success
          else
            :skipped
          end
        end
      rescue => e
        increment_retry(financial_report)
        raise e
      end

      # 保存记录，捕获数值溢出时逐个排除超限字段
      # 可靠做法：先全置 nil，再逐个赋值并保存，精确定位溢出字段
      def save_with_overflow_protection(record, financial_data)
        record.save!
      rescue ActiveRecord::StatementInvalid => e
        raise e unless e.message.include?("NumericValueOutOfRange")

        # 先全部置 nil
        financial_data.each_key { |key| record.send("#{key}=", nil) }

        # 逐个赋值并保存，找出溢出字段
        overflow_fields = []
        financial_data.each do |key, value|
          next if value.nil?

          record.send("#{key}=", value)
          begin
            record.save!
          rescue ActiveRecord::StatementInvalid
            overflow_fields << key
            record.send("#{key}=", nil)
          end
        end

        overflow_fields.each do |key|
          Rails.logger.warn "[#{self.class}] #{record.class}.#{key} 数值溢出(#{financial_data[key]}), 已置 nil"
        end
        record.save!
      end
    end
  end
end