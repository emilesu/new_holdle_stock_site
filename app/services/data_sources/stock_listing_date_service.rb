module DataSources
  # 同步 A股/港股/美股上市日期
  #   CN/HK：东方财富 F10 组织资料报表
  #   US：Yahoo v8 chart API 的 meta.firstTradeDate（首个交易日时间戳）
  # 增量策略：仅处理 listing_date 为空的股票，避免重复请求
  class StockListingDateService
    # 东方财富 F10 组织资料报表（CN/HK）
    REPORTS = {
      "CN" => "RPT_F10_ORG_BASICINFO",
      "HK" => "RPT_HKF10_INFO_ORGPROFILE"
    }.freeze

    # Yahoo chart API（美股）
    YAHOO_CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart".freeze
    YAHOO_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    YAHOO_TIMEOUT = 20
    YAHOO_RETRY_TIMES = 2
    YAHOO_RETRY_INTERVAL = 1

    # 支持的全部市场
    SUPPORTED_MARKETS = (REPORTS.keys + [ "US" ]).freeze

    # HTTP 非 2xx 响应（纳入重试范围）
    class RequestError < StandardError; end

    # 请求间隔（秒），避免触发数据源限流
    REQUEST_INTERVAL = 0.3

    class << self
      def call(market: nil, stock_ids: nil, after_stock_id: nil, limit: nil)
        Rails.logger.info "=" * 70
        Rails.logger.info "开始同步上市日期（CN/HK 东方财富 F10 + US Yahoo chart）"
        Rails.logger.info "=" * 70

        stats = { total: 0, updated: 0, skipped: 0, failed: 0 }
        markets = market.present? ? [ market ] : SUPPORTED_MARKETS

        remaining = limit.present? ? limit.to_i : nil

        targets = markets.filter_map do |m|
          next if remaining && remaining <= 0

          unless SUPPORTED_MARKETS.include?(m)
            Rails.logger.warn "市场 #{m} 暂不支持上市日期同步，跳过"
            next
          end

          stocks = Stock.where(market: m).where(listing_date: nil)
          stocks = stocks.where(id: stock_ids) if stock_ids.present?
          stocks = stocks.where("stocks.id > ?", after_stock_id.to_i) if after_stock_id.present?
          stocks = stocks.limit(remaining) if remaining
          remaining -= stocks.size if remaining
          [ m, stocks ]
        end

        stats[:total] = targets.sum { |_m, stocks| stocks.size }
        CrawlContext.current&.start!(total_count: stats[:total])

        targets.each do |m, stocks|
          target_count = stocks.size
          Rails.logger.info "[#{m}] 待同步 #{target_count} 只"

          processed = 0
          stocks.find_each do |stock|
            break if processed >= target_count

            ok = false
            begin
              date = if m == "US"
                fetch_us_listing_date(stock)
              else
                fetch_listing_date(REPORTS[m], secucode(stock))
              end

              if date && date <= Date.current
                stock.update_column(:listing_date, date)
                stats[:updated] += 1
                ok = true
              else
                stats[:skipped] += 1
                ok = true
                Rails.logger.warn "上市日期缺失或异常（未来日期）跳过 #{stock.symbol}: #{date}" if date
              end
            rescue => e
              stats[:failed] += 1
              Rails.logger.error "同步上市日期失败 #{stock.symbol}: #{e.message}"
            ensure
              SyncStateRecorder.record(stock, :listing_date, ok: ok)
              CrawlContext.current&.tick(unit_id: stock.id, ok: ok)
              processed += 1
              sleep REQUEST_INTERVAL
            end
          end
        end

        Rails.logger.info "统计结果：总条数 #{stats[:total]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"
        Rails.logger.info "上市日期同步完成"
        stats
      end

      private

      # 美股：通过 Yahoo chart API 的 meta.firstTradeDate 获取上市日期
      # firstTradeDate 是 Unix 时间戳（UTC），需按美东时区转换为当地日期
      def fetch_us_listing_date(stock)
        yahoo_sym = DataSources::YahooMonthlyBarService.yahoo_symbol(stock)
        return nil if yahoo_sym.nil?

        url = "#{YAHOO_CHART_URL}/#{yahoo_sym}?range=1d&interval=1d"
        body = yahoo_request(url)
        return nil if body.nil?

        data = JSON.parse(body)
        ts = data.dig("chart", "result", 0, "meta", "firstTradeDate")
        return nil if ts.nil?

        # 时间戳按美东时区转换为日期（交易所当地时间的首个交易日）
        ActiveSupport::TimeZone["America/New_York"].at(ts.to_i).to_date
      rescue JSON::ParserError => e
        Rails.logger.error "[ListingDate-US] #{stock.symbol} 响应解析失败：#{e.message}"
        nil
      end

      # Yahoo 请求（带重试），404 视为标的无数据返回 nil
      def yahoo_request(url)
        retries = YAHOO_RETRY_TIMES
        begin
          response = Faraday.get(url) do |req|
            req.headers["User-Agent"] = YAHOO_USER_AGENT
            req.options.timeout = YAHOO_TIMEOUT
            req.options.open_timeout = YAHOO_TIMEOUT
          end

          return nil if response.status == 404
          raise RequestError, "HTTP #{response.status}" unless response.success?

          body = response.body
          # HTTP 200 但 body 携带 chart.error（Yahoo 的 Not Found 也可能走这里）
          error = JSON.parse(body).dig("chart", "error") rescue nil
          if error.present?
            Rails.logger.warn "[ListingDate-US] Yahoo 返回业务错误：#{error["code"]} #{error["description"]}"
            return nil
          end

          body
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed, RequestError => e
          raise if retries.zero?

          retries -= 1
          Rails.logger.warn "[ListingDate-US] 请求异常，重试中（剩余 #{retries} 次）：#{e.message}"
          sleep YAHOO_RETRY_INTERVAL
          retry
        end
      end

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

      # 东方财富 F10 查询上市日期（CN/HK）
      def fetch_listing_date(report_name, secucode)
        data = EastmoneyDatacenter.fetch_data(
          report_name: report_name,
          columns: "SECUCODE,LISTING_DATE",
          filter: %((SECUCODE="#{secucode}")),
          page_size: 1,
          raise_on_failure: true
        )
        return nil unless data.present?

        listing = data.first&.dig("LISTING_DATE")
        listing.present? ? Date.parse(listing.to_s) : nil
      end
    end
  end
end
