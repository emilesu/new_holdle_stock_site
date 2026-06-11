module DataSources
  class NasdaqStockListService
    API_ENDPOINTS = {
      "NASDAQ" => "https://api.nasdaq.com/api/screener/stocks?tabletype=NASDAQ&exchange=NASDAQ",
      "NYSE" => "https://api.nasdaq.com/api/screener/stocks?tabletype=NYSE&exchange=NYSE",
      "AMEX" => "https://api.nasdaq.com/api/screener/stocks?tabletype=AMEX&exchange=AMEX"
    }.freeze

    SLEEP_SEC = 0.3

    class << self
      def call
        puts "=" * 70
        puts "开始爬取美股列表（NASDAQ/NYSE/AMEX）"
        puts "=" * 70

        API_ENDPOINTS.each_key do |market|
          fetch_market(market)
        end

        puts "\n✅ 美股列表爬取完成"
      end

      private

      def fetch_market(market)
        puts "\n正在抓取 #{market} 市场..."
        url = API_ENDPOINTS[market]

        response = Faraday.get(url, nil, {
          "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Accept" => "application/json"
        })

        if response.success?
          data = JSON.parse(response.body)
          # 修复点：rows 列表在 data['table']['rows'] 下
          stocks = data.dig("data", "table", "rows")
          return unless stocks.is_a?(Array)

          puts "获取到 #{stocks.size} 条数据"
          stocks.each do |item|
            save_stock(market, item)
            sleep SLEEP_SEC
          end

          puts "✅ #{market} 处理完成，共 #{stocks.size} 条"
        else
          puts "❌ #{market} 请求失败，状态码：#{response.status}"
        end
      rescue => e
        puts "❌ #{market} 请求异常：#{e.message}"
      end

      def save_stock(market, item)
        symbol = item["symbol"]
        return if symbol.blank?

        stock = Stock.find_or_initialize_by(
          symbol: symbol,
          market: "US"
        )

        stock.name = item["name"]
        stock.exchange = market
        stock.status = "listed"

        stock.save!
        puts "  入库：#{symbol} | #{item['name']}"
      rescue => e
        puts "❌ 入库失败 #{symbol}: #{e.message}"
      end
    end
  end
end