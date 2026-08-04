module DataSources
  # 同步 A股/港股上市日期（东方财富 F10 组织资料报表）
  # 增量策略：仅处理 listing_date 为空的股票，避免重复请求
  # 美股暂不支持（东方财富美股 F10 报表无上市日期字段），美股次新标签由"数据<5年"兜底
  class StockListingDateService
    EM_DATACENTER_URL = "https://datacenter.eastmoney.com/securities/api/data/v1/get".freeze
    EM_REFERER = "https://emweb.securities.eastmoney.com/".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 15
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1
    REQUEST_INTERVAL = 0.3

    # 市场 => 东方财富 F10 组织资料报表名
    REPORTS = {
      "CN" => "RPT_F10_ORG_BASICINFO",
      "HK" => "RPT_HKF10_INFO_ORGPROFILE"
    }.freeze

    class << self
      def call(market: nil)
        Rails.logger.info "=" * 70
        Rails.logger.info "开始同步上市日期（东方财富 F10）"
        Rails.logger.info "=" * 70

        stats = { total: 0, updated: 0, skipped: 0, failed: 0, api_error: 0 }
        markets = market.present? ? [market] : REPORTS.keys

        markets.each do |m|
          unless REPORTS.key?(m)
            Rails.logger.warn "市场 #{m} 暂不支持上市日期同步，跳过"
            next
          end

          stocks = Stock.where(market: m).where(listing_date: nil)
          stats[:total] += stocks.size
          Rails.logger.info "[#{m}] 待同步 #{stocks.size} 只"

          stocks.find_each do |stock|
            begin
              date = fetch_listing_date(REPORTS[m], secucode(stock))
              if date
                stock.update_column(:listing_date, date)
                stats[:updated] += 1
              else
                stats[:skipped] += 1
              end
            rescue => e
              stats[:failed] += 1
              Rails.logger.error "同步上市日期失败 #{stock.symbol}: #{e.message}"
            ensure
              sleep REQUEST_INTERVAL
            end
          end
        end

        Rails.logger.info "统计结果：总条数 #{stats[:total]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"
        Rails.logger.info "上市日期同步完成"
        stats
      end

      private

      # 库内 symbol → 东方财富 SECUCODE 格式（如 SH600519 → 600519.SH，00700.HK → 00700.HK）
      def secucode(stock)
        if stock.market == "CN"
          code = stock.symbol.sub(/\A[A-Z]{2}/, "")
          suffix = stock.symbol[0, 2].upcase
          "#{code}.#{suffix}"
        else
          stock.symbol
        end
      end

      def fetch_listing_date(report_name, secucode)
        retries = RETRY_TIMES

        begin
          response = Faraday.get(EM_DATACENTER_URL) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = EM_REFERER
            req.params.merge!({
              reportName: report_name,
              columns: "SECUCODE,LISTING_DATE",
              filter: %((SECUCODE="#{secucode}")),
              pageNumber: 1,
              pageSize: 1,
              sortTypes: "",
              sortColumns: "",
              source: "F10",
              client: "PC"
            })
            req.options.timeout = TIMEOUT
          end

          if response.success?
            data = JSON.parse(response.body).dig("result", "data")
            listing = data&.first&.dig("LISTING_DATE")
            listing.present? ? Date.parse(listing.to_s) : nil
          else
            Rails.logger.warn "#{secucode} 上市日期请求失败，状态码: #{response.status}"
            nil
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries -= 1
          if retries > 0
            Rails.logger.warn "#{secucode} 请求超时/断连，重试中（剩余 #{retries} 次）..."
            sleep RETRY_INTERVAL
            retry
          end
          Rails.logger.error "#{secucode} 请求失败（已重试 #{RETRY_TIMES} 次）: #{e.message}"
          nil
        rescue JSON::ParserError => e
          Rails.logger.error "#{secucode} JSON解析失败: #{e.message}"
          nil
        rescue => e
          Rails.logger.error "#{secucode} 请求异常: #{e.message}"
          nil
        end
      end
    end
  end
end
