module DataSources
  # 新浪财经 A 股列表爬虫（沪市/深市）
  class SinaCnStockListService < BaseSpiderService
    API_URL = "https://finance.sina.com.cn/stock/"
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    REFERER = "https://finance.sina.com.cn/"
    SLEEP_SEC = ENV.fetch("SPIDER_SLEEP_SEC", 0.3).to_f

    class << self
      def call
        puts "=" * 70
        puts "开始爬取 A 股列表（新浪财经）"
        puts "=" * 70

        # 这里先写框架，后续根据新浪接口实际返回字段补充逻辑
        puts "⚠️  新浪接口需要根据实际返回字段调整，先创建框架"
      end
    end
  end
end