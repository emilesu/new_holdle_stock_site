module DataSources
  class UsStockBasicInfoService
    # 雪球API获取中文名
    XUEQIU_QUOTE_URL = "https://stock.xueqiu.com/v5/stock/quote.json".freeze
    # Yahoo Finance API获取行业信息
    YAHOO_SEARCH_URL = "https://query1.finance.yahoo.com/v1/finance/search".freeze

    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

    TIMEOUT = 10

    # 行业板块(Sector)中英映射 - 根据 yahoo_list.md 更新
    SECTOR_MAPPING = {
      "Basic Materials" => "基础材料",
      "Communication Services" => "通信服务",
      "Consumer Cyclical" => "消费周期",
      "Consumer Defensive" => "消费防御",
      "Energy" => "能源",
      "Financial Services" => "金融服务",
      "Healthcare" => "医疗保健",
      "Industrials" => "工业",
      "Real Estate" => "房地产",
      "Technology" => "科技",
      "Utilities" => "公用事业",
      "Materials" => "原材料",
      "Consumer Discretionary" => "非必需消费品",
      "Consumer Staples" => "必需消费品",
      "Health Care" => "医疗保健",
      "Financials" => "金融",
      "Information Technology" => "信息技术"
    }.freeze

    # 行业(Industry)中英映射 - 根据 yahoo_list.md 更新
    INDUSTRY_MAPPING = {
      # Basic Materials 基础材料
      "Agribusiness" => "农业综合",
      "Aluminum" => "铝",
      "Building Materials" => "建材",
      "Chemicals" => "化工",
      "Copper" => "铜",
      "Gold" => "黄金",
      "Lumber & Wood Production" => "木材与木制品",
      "Metal Fabrication" => "金属加工",
      "Mining" => "采矿",
      "Nonferrous Metals" => "有色金属",
      "Paper & Paper Products" => "造纸",
      "Silver" => "白银",
      "Specialty Chemicals" => "特种化工",
      
      # Communication Services 通信服务
      "Advertising Agencies" => "广告代理",
      "Broadcasting" => "广播电视",
      "Entertainment" => "娱乐",
      "Internet Content & Information" => "互联网内容与信息",
      "Media" => "传媒",
      "Telecom Services" => "电信服务",
      
      # Consumer Cyclical 消费周期
      "Apparel Manufacturing" => "服装制造",
      "Auto & Truck Dealerships" => "汽车经销",
      "Auto Manufacturers" => "汽车制造",
      "Auto Parts" => "汽车零部件",
      "Furnishings, Fixtures & Appliances" => "家居与家电",
      "Gambling" => "博彩",
      "Home Improvement Retail" => "家居零售",
      "Luxury Goods" => "奢侈品",
      "Packaging & Containers" => "包装",
      "Personal Services" => "个人服务",
      "Recreational Vehicles" => "休闲车",
      "Residential Construction" => "住宅建造",
      "Retail—Apparel & Specialty" => "服装零售",
      "Textile Manufacturing" => "纺织制造",
      "Internet Retail" => "互联网零售",
      
      # Consumer Defensive 消费防御
      "Beverages—Alcoholic" => "酒精饮料",
      "Beverages—Non-Alcoholic" => "非酒精饮料",
      "Confectioners" => "糖果",
      "Discount Stores" => "折扣零售",
      "Food Distribution" => "食品分销",
      "Food Products" => "食品",
      "Household & Personal Products" => "家居个人用品",
      "Packaged Foods" => "包装食品",
      "Tobacco" => "烟草",
      
      # Energy 能源
      "Oil & Gas Drilling" => "油气钻井",
      "Oil & Gas E&P" => "油气勘探开采",
      "Oil & Gas Integrated" => "综合油气",
      "Oil & Gas Midstream" => "油气中游",
      "Oil & Gas Refining & Marketing" => "油气炼化销售",
      "Oil & Gas Services" => "油气服务",
      "Renewable Energy" => "可再生能源",
      
      # Financial Services 金融服务
      "Asset Management" => "资产管理",
      "Banks—Diversified" => "多元化银行",
      "Banks—Regional" => "地区银行",
      "Capital Markets" => "资本市场",
      "Credit Services" => "信用服务",
      "Financial Data & Stock Exchanges" => "金融数据与交易所",
      "Insurance—Diversified" => "综合保险",
      "Insurance—Life" => "寿险",
      "Insurance—Property & Casualty" => "财险",
      "Insurance—Reinsurance" => "再保险",
      "Mortgage Finance" => "抵押金融",
      "Real Estate" => "房地产",
      "Real Estate—Development" => "地产开发",
      "Real Estate—Diversified" => "综合地产",
      "Real Estate—REITs" => "房地产信托",
      "Savings & Cooperative Banks" => "储蓄合作银行",
      
      # Healthcare 医疗保健
      "Biotechnology" => "生物技术",
      "Drug Manufacturers—General" => "综合制药",
      "Drug Manufacturers—Specialty" => "专科制药",
      "Healthcare Equipment" => "医疗设备",
      "Healthcare Plans" => "医保计划",
      "Medical Devices" => "医疗器械",
      "Medical Diagnostics & Research" => "医疗诊断与研究",
      "Medical Distribution" => "医药分销",
      "Pharmaceutical Retailers" => "医药零售",
      
      # Industrials 工业
      "Aerospace & Defense" => "航空航天国防",
      "Airlines" => "航空",
      "Building Products" => "建筑产品",
      "Business Services" => "商业服务",
      "Construction" => "建筑工程",
      "Consulting Services" => "咨询服务",
      "Electrical Equipment" => "电气设备",
      "Engineering & Construction" => "工程建设",
      "Farm & Heavy Construction Machinery" => "农业与重型工程机械",
      "Freight & Logistics" => "货运物流",
      "Industrial Distribution" => "工业分销",
      "Infrastructure Operations" => "基建运营",
      "Marine Shipping" => "海运",
      "Metalworking Equipment" => "金属加工设备",
      "Office Supplies" => "办公用品",
      "Railroads" => "铁路",
      "Security & Protection" => "安防",
      "Staffing & Employment Services" => "人力服务",
      "Tools & Accessories" => "工具配件",
      
      # Real Estate 房地产
      "Real Estate—Residential" => "住宅地产",
      "Real Estate—Commercial" => "商业地产",
      "Real Estate—Industrial" => "工业地产",
      "Real Estate—Retail" => "零售地产",
      "Real Estate—Hospitality" => "酒店地产",
      
      # Technology 科技
      "Application Software" => "应用软件",
      "Communication Equipment" => "通信设备",
      "Computer Hardware" => "计算机硬件",
      "Consumer Electronics" => "消费电子",
      "Electronic Components" => "电子元器件",
      "Information Technology Services" => "信息技术服务",
      "Internet Software & Services" => "互联网软件服务",
      "Semiconductors" => "半导体",
      "Semiconductor Equipment" => "半导体设备",
      "Solar" => "太阳能",
      "Software—Application" => "应用软件",
      "Software—Infrastructure" => "基础设施软件",
      "Tech Hardware, Storage & Peripherals" => "硬件存储外设",
      "Software - Infrastructure" => "基础设施软件",
      "Software - Application" => "应用软件",
      
      # Utilities 公用事业
      "Electric Utilities" => "电力公用",
      "Gas Utilities" => "燃气公用",
      "Water Utilities" => "水务公用",
      "Renewable Utilities" => "可再生公用",
      
      # 额外补充的行业映射
      "Uranium" => "铀",
      "Conglomerates" => "企业集团",
      "Steel" => "钢铁",
      "Medical Care Facilities" => "医疗护理设施",
      "Other Industrial Metals & Mining" => "其他工业金属和采矿"
    }.freeze

    class << self
      def call(ticker)
        puts "=" * 70
        puts "开始爬取美股基础信息 | 股票代码: #{ticker}"
        puts "=" * 70

        stock = Stock.find_by(symbol: ticker, market: "US")
        unless stock
          puts "❌ 未找到股票记录: #{ticker} (US)"
          return
        end

        puts "找到股票 ID: #{stock.id}, 当前名称: #{stock.name}"

        # 获取中文名（雪球）
        chinese_name = fetch_chinese_name(ticker)
        
        # 获取行业信息（Yahoo Finance）
        industry_info = fetch_industry_info(ticker)

        if chinese_name.blank? && industry_info.blank?
          puts "❌ 未能获取任何有效数据"
          return
        end

        update_stock(stock, chinese_name, industry_info)

        puts "\n✅ 股票基础信息爬取完成"
      rescue => e
        puts "❌ 爬取过程异常: #{e.message}"
        puts e.backtrace.take(5).join("\n")
      end

      private

      def fetch_chinese_name(ticker)
        puts "\n[1/2] 正在从雪球获取中文名..."

        begin
          response = Faraday.get(XUEQIU_QUOTE_URL) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = "https://xueqiu.com/"
            req.headers["Cookie"] = ENV["XUEQIU_COOKIE"].presence || ""
            req.params['symbol'] = ticker
            req.params['extend'] = 'detail'
            req.options.timeout = TIMEOUT
          end

          if response.success?
            data = JSON.parse(response.body)
            name = data.dig("data", "quote", "name")
            puts "✅ 雪球返回中文名: #{name}"
            return name
          else
            puts "⚠️  雪球请求失败，状态码: #{response.status}"
            return nil
          end
        rescue => e
          puts "⚠️  雪球请求异常: #{e.message}"
          return nil
        end
      end

      def fetch_industry_info(ticker)
        puts "\n[2/2] 正在从Yahoo Finance获取行业信息..."

        begin
          response = Faraday.get(YAHOO_SEARCH_URL) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = "https://finance.yahoo.com/"
            req.params['q'] = ticker
            req.options.timeout = TIMEOUT
          end

          if response.success?
            data = JSON.parse(response.body)
            quotes = data["quotes"]
            
            if quotes && quotes.any?
              stock_data = quotes.find { |q| q["symbol"] == ticker }
              if stock_data
                # 获取英文行业和板块
                english_industry = stock_data["industry"] || stock_data["industryDisp"]
                english_sector = stock_data["sector"] || stock_data["sectorDisp"]
                
                # 转换为中文
                chinese_industry = INDUSTRY_MAPPING[english_industry] || english_industry
                chinese_sector = SECTOR_MAPPING[english_sector] || english_sector
                
                puts "✅ Yahoo返回行业信息:"
                puts "  - 板块(英文): #{english_sector} → 中文: #{chinese_sector}"
                puts "  - 行业(英文): #{english_industry} → 中文: #{chinese_industry}"
                
                return { sector: chinese_sector, industry: chinese_industry }
              end
            end
            puts "⚠️  未找到匹配的股票数据"
            return nil
          else
            puts "⚠️  Yahoo请求失败，状态码: #{response.status}"
            return nil
          end
        rescue => e
          puts "⚠️  Yahoo请求异常: #{e.message}"
          return nil
        end
      end

      def stock_english_name(symbol)
        names = {
          "MSFT" => "Microsoft Corporation Common Stock",
          "AAPL" => "Apple Inc. Common Stock",
          "NVDA" => "NVIDIA Corporation Common Stock",
          "GOOGL" => "Alphabet Inc. Class A Common Stock",
          "GOOG" => "Alphabet Inc. Class C Capital Stock",
          "AMZN" => "Amazon.com Inc. Common Stock",
          "META" => "Meta Platforms Inc. Class A Common Stock",
          "TSLA" => "Tesla Inc. Common Stock",
          "BRK.B" => "Berkshire Hathaway Inc. Class B Common Stock",
          "JPM" => "JPMorgan Chase & Co. Common Stock",
          "JNJ" => "Johnson & Johnson Common Stock",
          "V" => "Visa Inc. Common Stock",
          "PG" => "Procter & Gamble Company Common Stock",
          "MA" => "Mastercard Incorporated Common Stock",
          "HD" => "Home Depot Inc. Common Stock",
          "DIS" => "Walt Disney Company Common Stock",
          "NFLX" => "Netflix Inc. Common Stock",
          "PYPL" => "PayPal Holdings Inc. Common Stock",
          "INTC" => "Intel Corporation Common Stock",
          "AMD" => "Advanced Micro Devices Inc. Common Stock",
          "CSCO" => "Cisco Systems Inc. Common Stock",
          "PEP" => "PepsiCo Inc. Common Stock",
          "KO" => "Coca-Cola Company Common Stock",
          "NKE" => "Nike Inc. Common Stock",
          "ADBE" => "Adobe Inc. Common Stock",
          "CRM" => "Salesforce Inc. Common Stock",
          "ORCL" => "Oracle Corporation Common Stock",
          "IBM" => "International Business Machines Corporation Common Stock",
          "QCOM" => "Qualcomm Incorporated Common Stock",
          "TXN" => "Texas Instruments Incorporated Common Stock"
        }
        names[symbol] || "#{symbol} Common Stock"
      end

      def update_stock(stock, chinese_name, industry_info)
        english_name = stock_english_name(stock.symbol)
        
        # 组装新名称
        new_name = if chinese_name.present? && english_name.present?
                     "#{chinese_name} | #{english_name}"
                   elsif english_name.present?
                     english_name
                   else
                     stock.name
                   end

        # 获取行业和板块信息
        new_sector = industry_info ? industry_info[:sector] : stock.sector
        new_industry = industry_info ? industry_info[:industry] : stock.industry

        old_name = stock.name
        old_sector = stock.sector
        old_industry = stock.industry

        if new_name == old_name && new_sector == old_sector && new_industry == old_industry
          puts "⏭️ 名称/板块/行业无变化，跳过更新"
        else
          stock.name = new_name
          stock.sector = new_sector if new_sector.present?
          stock.industry = new_industry if new_industry.present?
          stock.save!
          puts "✅ 股票信息发生变更，已完成覆盖更新"
          puts "  - 名称: #{old_name} → #{new_name}" unless new_name == old_name
          puts "  - 板块: #{old_sector || '（无）'} → #{new_sector || '（无）'}" unless new_sector == old_sector
          puts "  - 行业: #{old_industry || '（无）'} → #{new_industry || '（无）'}" unless new_industry == old_industry
        end
      end
    end
  end
end