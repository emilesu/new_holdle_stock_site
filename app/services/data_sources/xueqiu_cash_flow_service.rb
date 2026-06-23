module DataSources
  class XueqiuCashFlowService
    US_BASE_URL = "https://stock.xueqiu.com/v5/stock/finance/us/cash_flow.json".freeze
    CN_BASE_URL = "https://stock.xueqiu.com/v5/stock/finance/cn/cash_flow.json".freeze

    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    REFERER = "https://xueqiu.com/".freeze

    TIMEOUT = 10
    RETRY_MAX = 3
    RETRY_DELAY = 2

    MAX_YEARS_BACK = 10
    ALLOWED_REPORT_TYPES = [:annual].freeze

    class << self
      def call(symbol, market: "US")
        puts "=" * 70
        puts "开始爬取雪球#{market == 'CN' ? 'A股' : '美股'}现金流量表数据"
        puts "股票代码: #{symbol}, 市场: #{market}"
        puts "=" * 70

        stock = Stock.find_by(symbol: symbol, market: market)
        unless stock
          puts "❌ 未找到股票: #{symbol} (#{market})"
          return
        end

        puts "找到股票 ID: #{stock.id}, 名称: #{stock.name}"

        response = fetch_data(symbol, market)
        return unless response

        parse_and_save(stock, response, market)

        puts "\n✅ 现金流量表数据爬取完成"
      rescue => e
        puts "❌ 爬取过程异常: #{e.message}"
        puts e.backtrace.take(5).join("\n")
      end

      private

      def fetch_data(symbol, market)
        puts "\n正在请求雪球现金流量表接口..."

        base_url = market == 'CN' ? CN_BASE_URL : US_BASE_URL
        
        connection = Faraday.new(
          url: base_url,
          headers: default_headers,
          request: {
            timeout: TIMEOUT,
            open_timeout: TIMEOUT
          }
        ) do |conn|
          conn.response :json
          conn.adapter Faraday.default_adapter
        end

        retries = 0
        begin
          response = connection.get do |req|
            req.params['symbol'] = symbol
            req.params['type'] = 'all'
            req.params['count'] = 40
          end

          if response.success?
            puts "✅ 接口请求成功，状态码: #{response.status}"
            return response.body
          else
            puts "❌ 接口请求失败，状态码: #{response.status}"
            return nil
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries += 1
          if retries <= RETRY_MAX
            puts "⚠️ 请求超时/连接失败，重试第 #{retries}/#{RETRY_MAX} 次"
            sleep RETRY_DELAY
            retry
          else
            puts "❌ 请求重试 #{RETRY_MAX} 次后仍失败: #{e.message}"
            return nil
          end
        rescue => e
          puts "❌ 请求异常: #{e.message}"
          return nil
        end
      end

      def default_headers
        cookie = ENV["XUEQIU_COOKIE"].presence || ""
        {
          "User-Agent" => USER_AGENT,
          "Referer" => REFERER,
          "Cookie" => cookie,
          "Accept" => "application/json",
          "Accept-Language" => "zh-CN,zh;q=0.9,en;q=0.8"
        }
      end

      def parse_and_save(stock, data, market)
        return unless data.is_a?(Hash)

        items = data.dig("data", "list")
        unless items.is_a?(Array)
          puts "❌ 未找到财报数据列表"
          return
        end

        puts "\n接口返回原始数据：#{items.size}条"

        filtered_items = filter_items(items)

        puts "过滤后有效数据（近#{MAX_YEARS_BACK}年年报）：#{filtered_items.size}条"

        success_count = 0
        fail_count = 0
        skip_count = 0

        filtered_items.each do |item|
          begin
            result = save_cash_flow(stock, item, market)
            if result == :skipped
              skip_count += 1
            else
              success_count += 1
            end
          rescue => e
            fail_count += 1
            puts "❌ 单条数据入库失败: #{e.message}"
          end
        end

        puts "\n📊 入库统计: 成功 #{success_count} 条, 跳过 #{skip_count} 条, 失败 #{fail_count} 条"
      end

      def filter_items(items)
        filtered = []
        expired_count = 0
        non_annual_count = 0

        items.each do |item|
          report_date = parse_date(item["report_date"])
          report_type_code = item["report_type_code"]
          report_name = item["report_name"]

          unless report_date
            non_annual_count += 1
            next
          end

          if report_date < MAX_YEARS_BACK.years.ago.to_date
            expired_count += 1
            puts "⏭️ 跳过过期数据：报告日期=#{report_date.strftime('%Y-%m-%d')}"
            next
          end

          unless is_annual_report?(report_type_code, report_name)
            non_annual_count += 1
            puts "⏭️ 跳过非年报数据：报告日期=#{report_date.strftime('%Y-%m-%d')}，类型=#{report_type_code}"
            next
          end

          filtered << item
        end

        puts "  - 过期数据跳过: #{expired_count}条" if expired_count > 0
        puts "  - 非年报数据跳过: #{non_annual_count}条" if non_annual_count > 0

        filtered
      end

      def is_annual_report?(report_type_code, report_name)
        report_type_code = report_type_code.to_s
        report_name = report_name.to_s

        report_type_code == '596001' || report_name.include?('年报')
      end

      def save_cash_flow(stock, item, market)
        timestamp = item["report_date"]
        report_date = parse_date(timestamp)
        report_type = item["report_type_code"]
        report_name = item["report_name"]

        unless report_date
          puts "❌ 处理失败：时间戳=#{timestamp}，错误原因=无效的时间戳格式"
          return :skipped
        end

        puts "  处理成功：财报日期=#{report_date.strftime('%Y-%m-%d')} | #{report_name}"

        financial_report = FinancialReport.find_or_initialize_by(
          stock_id: stock.id,
          report_date: report_date,
          report_type: report_type,
          market: market
        )

        financial_report.market = market
        financial_report.save!
        puts "  主表匹配/创建：报告ID=#{financial_report.id}"

        financial_data = parse_financial_fields(item, market)
        operating_cash_flow = financial_data[:operating_cash_flow]
        investing_cash_flow = financial_data[:investing_cash_flow]
        financing_cash_flow = financial_data[:financing_cash_flow]
        
        net_cash_change = financial_data[:net_cash_change]
        if net_cash_change.nil?
          net_cash_change = calculate_net_cash_change(operating_cash_flow, investing_cash_flow, financing_cash_flow)
          puts "  ⚠️  API未返回净现金变动，已计算得出: #{net_cash_change}"
        end

        if CashFlow.exists?(financial_report_id: financial_report.id)
          cash_flow = CashFlow.find_by(financial_report_id: financial_report.id)
          new_data = {
            report_type: report_type,
            operating_cash_flow: operating_cash_flow,
            investing_cash_flow: investing_cash_flow,
            financing_cash_flow: financing_cash_flow,
            net_cash_change: net_cash_change
          }

          if data_changed?(cash_flow, new_data)
            update_cash_flow(cash_flow, new_data)
            financial_report.last_crawled_at = Time.current
            financial_report.save!
            puts "  ✅ 数据存在变更，已覆盖更新：报告ID=#{financial_report.id}"
          else
            puts "  ⏭️ 数据无变化，跳过更新：报告ID=#{financial_report.id}"
            return :skipped
          end
        else
          cash_flow = CashFlow.new(
            financial_report_id: financial_report.id,
            stock_id: stock.id,
            report_date: report_date,
            market: market,
            report_type: report_type,
            operating_cash_flow: operating_cash_flow,
            investing_cash_flow: investing_cash_flow,
            financing_cash_flow: financing_cash_flow,
            net_cash_change: net_cash_change
          )
          cash_flow.save!
          financial_report.last_crawled_at = Time.current
          financial_report.save!
          puts "  ✅ 新数据写入成功：报告ID=#{financial_report.id}"
        end
      rescue => e
        financial_report&.update(retry_count: (financial_report.retry_count || 0) + 1)
        raise e
      end

      def parse_financial_fields(item, market)
        if market == 'CN'
          {
            operating_cash_flow: parse_financial_value(item["ncf_from_oa"]),
            investing_cash_flow: parse_financial_value(item["ncf_from_ia"]),
            financing_cash_flow: parse_financial_value(item["ncf_from_fa"]),
            net_cash_change: nil,
          }
        else
          {
            operating_cash_flow: parse_financial_value(item["net_cash_provided_by_oa"]),
            investing_cash_flow: parse_financial_value(item["net_cash_used_in_ia"]),
            financing_cash_flow: parse_financial_value(item["net_cash_used_in_fa"]),
            net_cash_change: parse_financial_value(item["net_cash_change"])
          }
        end
      end

      def calculate_net_cash_change(operating, investing, financing)
        result = 0
        result += operating.to_d if operating
        result += investing.to_d if investing
        result += financing.to_d if financing
        result == 0 ? nil : result
      end

      def data_changed?(record, new_data)
        new_data.each do |key, value|
          return true if record.send(key) != value
        end
        false
      end

      def update_cash_flow(record, new_data)
        new_data.each do |key, value|
          record.send("#{key}=", value)
        end
        record.save!
      end

      def parse_date(timestamp)
        return nil unless timestamp.present?

        timestamp = timestamp.to_i
        if timestamp.to_s.length >= 12
          Time.zone.at(timestamp / 1000).to_date
        else
          Time.zone.at(timestamp).to_date
        end
      rescue => e
        puts "时间戳转换失败：#{timestamp}，错误: #{e.message}"
        nil
      end

      def parse_financial_value(value)
        return nil unless value.is_a?(Array) && value.any?

        BigDecimal(value.first.to_s)
      rescue
        nil
      end
    end
  end
end