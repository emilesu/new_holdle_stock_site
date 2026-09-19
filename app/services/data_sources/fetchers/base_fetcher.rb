require "set"

module DataSources
  module Fetchers
    # 东方财富财务数据抓取器基类
    # 封装通用逻辑：HTTP客户端、重试、日期解析、FinancialReport 匹配
    class BaseFetcher
      BASE_URL = "https://datacenter.eastmoney.com/securities/api/data/v1/get".freeze
      TIMEOUT = 15
      RETRY_MAX = 3
      RETRY_DELAY = 2
      MAX_YEARS_BACK = 20
      # 季报只保留近 16 期（约 4 年），满足「最近一期 + 去年同期 + 近 16 期趋势图」
      MAX_QUARTERS_BACK = 16

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
      # period_type 仅作为属性写入，不参与唯一键（同一报告日期只保留一条主记录）
      def find_or_create_financial_report(stock, report_date:, report_type:, market:, period_type: "annual")
        financial_report = FinancialReport.find_or_initialize_by(
          stock_id: stock.id,
          report_date: report_date,
          report_type: report_type,
          market: market
        )
        financial_report.market = market
        financial_report.period_type = period_type
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

      # 按报告日期推断 A 股期次类型（A 股财年固定 12-31）
      # 报表类型由 DATE_TYPE_CODE 优先判定；此方法作为兜底（如无类型字段的指标表）
      def period_type_for_date(report_date)
        return "annual" unless report_date.respond_to?(:month)
        case report_date.month
        when 3 then "q1"
        when 6 then "h1"
        when 9 then "q3"
        else "annual"
        end
      end

      # 通用年限过滤：报告日期是否在最近 years 年内
      def within_years?(report_date, years)
        report_date >= years.years.ago.to_date
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

      # 保留策略：年报近 MAX_YEARS_BACK 年 + 季报近 MAX_QUARTERS_BACK 期
      # entries: [{ report_date: Date, period_type: String }, ...]
      # 返回允许入库的期次集合，元素为 [period_type, report_date]
      def retention_period_set(entries)
        annual_cutoff = MAX_YEARS_BACK.years.ago.to_date
        annual = entries.select { |e| e[:period_type] == "annual" && e[:report_date] >= annual_cutoff }
        quarters = entries.reject { |e| e[:period_type] == "annual" }
                          .uniq { |e| e[:report_date] }
                          .sort_by { |e| e[:report_date] }
                          .last(MAX_QUARTERS_BACK)
        (annual + quarters).map { |e| [ e[:period_type], e[:report_date] ] }.to_set
      end

      # 引用 financial_report 的子表模型（清理残留记录时用于引用检查）
      CHILD_MODELS = [ IncomeStatement, BalanceSheet, CashFlow, FinancialIndicator ].freeze

      # 清理该股票不在保留期次内的记录
      # 按 (period_type, report_date) 组合判定：历史抓取时 period_type 尚未存在（默认 annual），
      # 只比日期无法剔除「中报/季报被标成年报」的误标记录，会污染 get_financial_data_by_year 的年报取数
      def cleanup_stale_records(stock, market, periods)
        allowed = periods.map { |p| [ p[:period_type], p[:report_date] ] }.to_set
        removed = 0

        CHILD_MODELS.each do |model|
          stale_ids = stale_ids_for(model, stock, market, allowed)
          removed += model.where(id: stale_ids).delete_all if stale_ids.any?
        end

        # 主记录最后清理：仅删除已无子表引用的孤儿记录，避免外键约束报错
        stale_report_ids = stale_ids_for(FinancialReport, stock, market, allowed)
        if stale_report_ids.any?
          referenced = CHILD_MODELS.flat_map do |model|
            model.where(financial_report_id: stale_report_ids).distinct.pluck(:financial_report_id)
          end
          removable = stale_report_ids - referenced
          removed += FinancialReport.where(id: removable).delete_all if removable.any?
        end

        Rails.logger.info "[#{self.class}] #{stock.symbol} 清理非保留期次记录 #{removed} 条" if removed > 0
        removed
      end

      # 取出 (period_type, report_date) 不在保留期次内的记录 id
      def stale_ids_for(model, stock, market, allowed)
        model.where(stock_id: stock.id, market: market)
             .pluck(:id, :period_type, :report_date)
             .reject { |(_id, period_type, report_date)| allowed.include?([ period_type, report_date ]) }
             .map(&:first)
      end

      # 统一保存逻辑：检测存在/变更，新建或更新
      # 使用 (stock_id, report_date, market) 唯一约束进行查找，避免重复插入
      # 子类必须定义 REPORT_TYPE_CODE 常量
      def save_model_record(stock, financial_report, model_class, report_date, market, financial_data, period_type: "annual")
        report_type = financial_data.delete(:report_type) || self.class::REPORT_TYPE_CODE

        record = model_class.find_or_initialize_by(
          stock_id: stock.id,
          report_date: report_date,
          market: market
        )

        if record.new_record?
          record.assign_attributes(
            financial_report_id: financial_report.id,
            report_type: report_type,
            period_type: period_type
          )
          financial_data.each { |k, v| record.send("#{k}=", v) }
          save_with_overflow_protection(record, financial_data)
          mark_crawled(financial_report)
          Rails.logger.info "[#{self.class}] #{model_class} 新建记录: stock=#{stock.symbol}, date=#{report_date}, period=#{period_type}, market=#{market}"
          :success
        else
          new_data = financial_data.merge(report_type: report_type, period_type: period_type)

          if data_changed?(record, new_data)
            record.financial_report_id = financial_report.id
            financial_data.each { |k, v| record.send("#{k}=", v) }
            # report_type / period_type 不在 financial_data 中，需显式写入：
            # 否则历史误标期次（如把中报当年报入库）永远无法被修正
            record.report_type = report_type
            record.period_type = period_type
            save_with_overflow_protection(record, financial_data)
            mark_crawled(financial_report)
            Rails.logger.info "[#{self.class}] #{model_class} 更新记录: stock=#{stock.symbol}, date=#{report_date}, period=#{period_type}, market=#{market}"
            :success
          else
            Rails.logger.info "[#{self.class}] #{model_class} 跳过记录: stock=#{stock.symbol}, date=#{report_date}, period=#{period_type}, market=#{market} (数据无变化，字段数=#{new_data.size})"
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