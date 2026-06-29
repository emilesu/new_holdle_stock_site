module DataSources
  class NasdaqStockListService
    API_ENDPOINTS = {
      "NASDAQ" => "https://api.nasdaq.com/api/screener/stocks?tabletype=NASDAQ&exchange=NASDAQ&limit=5000",
      "NYSE" => "https://api.nasdaq.com/api/screener/stocks?tabletype=NYSE&exchange=NYSE&limit=5000",
      "AMEX" => "https://api.nasdaq.com/api/screener/stocks?tabletype=AMEX&exchange=AMEX&limit=5000"
    }.freeze

    TIMEOUT = 30
    RETRY_TIMES = 2
    RETRY_INTERVAL = 2

    class << self
      def call
        Rails.logger.info "=" * 70
        Rails.logger.info "开始爬取美股列表（NASDAQ/NYSE/AMEX）"
        Rails.logger.info "=" * 70

        stats = { total: 0, created: 0, updated: 0, skipped: 0, failed: 0 }

        API_ENDPOINTS.each_key do |market|
          market_stats = fetch_market(market)
          merge_stats(stats, market_stats)
        end

        Rails.logger.info "=" * 70
        Rails.logger.info "美股列表爬取完成"
        Rails.logger.info "📊 统计: 总计 #{stats[:total]}, 新增 #{stats[:created]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"
        Rails.logger.info "=" * 70

        stats
      end

      private

      def fetch_market(market)
        Rails.logger.info "正在抓取 #{market} 市场..."
        url = API_ENDPOINTS[market]

        stats = { total: 0, created: 0, updated: 0, skipped: 0, failed: 0 }

        existing_stocks = Stock.where(market: "US").index_by(&:symbol)

        retries = RETRY_TIMES
        begin
          response = Faraday.get(url, nil, {
            "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept" => "application/json"
          }) do |req|
            req.options.timeout = TIMEOUT
          end

          if response.success?
            data = JSON.parse(response.body)
            stocks = data.dig("data", "table", "rows")
            unless stocks.is_a?(Array) && stocks.any?
              Rails.logger.warn "#{market} 返回数据为空"
              return stats
            end

            total_records = data.dig("data", "totalrecords") || stocks.size
            Rails.logger.info "#{market} 获取到 #{stocks.size} 条（总计约 #{total_records} 条）"

            stats[:total] = stocks.size

            stocks.each do |item|
              result = save_stock(market, item, existing_stocks)
              stats[result] += 1
            end

            Rails.logger.info "✅ #{market} 处理完成: 新增 #{stats[:created]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"
          else
            Rails.logger.error "❌ #{market} 请求失败，状态码：#{response.status}"
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries -= 1
          if retries >= 0
            Rails.logger.warn "#{market} 请求超时/断连，重试中（剩余 #{retries + 1} 次）..."
            sleep RETRY_INTERVAL
            retry
          end
          Rails.logger.error "#{market} 请求失败（已重试）: #{e.message}"
        rescue JSON::ParserError => e
          Rails.logger.error "#{market} JSON 解析失败: #{e.message}"
        rescue => e
          Rails.logger.error "#{market} 请求异常: #{e.message}"
        end

        stats
      end

      def save_stock(market, item, existing_stocks = {})
        symbol = item["symbol"]
        return :failed if symbol.blank?

        name = item["name"]
        return :failed if name.blank?

        existing = existing_stocks[symbol]
        if existing
          # 不覆盖 name 字段，保留已有的中文名/组合名
          # 仅更新 exchange 和 status
          if existing.exchange == market
            return :skipped
          end
          existing.exchange = market
          existing.status = "listed"
          existing.save!
          return :updated
        end

        Stock.create!(
          symbol: symbol,
          name: name,
          market: "US",
          exchange: market,
          status: "listed"
        )

        :created
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "入库失败 #{symbol}: #{e.message}"
        :failed
      rescue => e
        Rails.logger.error "入库异常 #{symbol}: #{e.message}"
        :failed
      end

      def merge_stats(target, source)
        %i[total created updated skipped failed].each do |key|
          target[key] += source[key] if source[key]
        end
      end
    end
  end
end