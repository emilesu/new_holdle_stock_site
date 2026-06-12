module DataSources
  class UsStockBasicInfoService
    # 雪球API获取中文名
    XUEQIU_QUOTE_URL = "https://stock.xueqiu.com/v5/stock/quote.json".freeze
    # Yahoo Finance API获取行业信息
    YAHOO_SEARCH_URL = "https://query1.finance.yahoo.com/v1/finance/search".freeze

    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze

    TIMEOUT = 10

    # 行业板块(Sector)中英映射
    SECTOR_MAPPING = {
      "Energy" => "能源",
      "Materials" => "原材料",
      "Industrials" => "工业",
      "Consumer Discretionary" => "非必需消费品",
      "Consumer Staples" => "必需消费品",
      "Health Care" => "医疗保健",
      "Financials" => "金融",
      "Information Technology" => "信息技术",
      "Technology" => "科技",
      "Communication Services" => "通信服务",
      "Utilities" => "公用事业",
      "Real Estate" => "房地产"
    }.freeze

    # 行业(Industry)中英映射 - 根据 yahoo_list.md 更新
    INDUSTRY_MAPPING = {
      # Energy 能源
      "Oil & Gas Exploration & Production" => "油气勘探与生产",
      "Oil & Gas Refining & Marketing" => "油气炼制与销售",
      "Oil & Gas Equipment & Services" => "油气设备与服务",
      "Integrated Oil & Gas" => "综合油气",
      "Thermal Coal" => "动力煤",
      "Renewable Energy" => "可再生能源",
      
      # Materials 原材料
      "Chemicals" => "化工",
      "Specialty Chemicals" => "特种化工",
      "Metals & Mining" => "金属与采矿",
      "Steel" => "钢铁",
      "Paper & Forest Products" => "造纸与林业产品",
      "Construction Materials" => "建筑材料",
      "Containers & Packaging" => "包装容器",
      "Precious Metals & Minerals" => "贵金属与矿产",
      
      # Industrials 工业
      "Aerospace & Defense" => "航空航天与国防",
      "Machinery" => "机械",
      "Specialty Industrial Machinery" => "专用工业机械",
      "Electrical Equipment" => "电气设备",
      "Construction & Engineering" => "建筑与工程",
      "Transportation" => "交通运输",
      "Railroads" => "铁路",
      "Trucking" => "卡车运输",
      "Airlines" => "航空",
      "Air Freight & Logistics" => "空运与物流",
      "Business Services" => "商业服务",
      "Waste Management" => "废物管理",
      "Security & Protection Services" => "安全防护服务",
      "Human Resource & Employment Services" => "人力资源服务",
      
      # Consumer Discretionary 非必需消费品
      "Auto Manufacturers" => "汽车制造",
      "Auto Parts" => "汽车零部件",
      "Apparel Retail" => "服装零售",
      "Apparel Manufacturing" => "服装制造",
      "Specialty Retail" => "专业零售",
      "Internet Retail" => "互联网零售",
      "Restaurants" => "餐饮",
      "Lodging" => "酒店住宿",
      "Leisure" => "休闲娱乐",
      "Gambling" => "博彩",
      "Luxury Goods" => "奢侈品",
      "Home Improvement Retail" => "家居零售",
      "Toys & Games" => "玩具与游戏",
      "Textiles" => "纺织品",
      
      # Consumer Staples 必需消费品
      "Packaged Foods" => "包装食品",
      "Beverages" => "饮料",
      "Household & Personal Products" => "家居与个人护理用品",
      "Grocery Stores" => "食品杂货零售",
      "Tobacco" => "烟草",
      "Food Distribution" => "食品分销",
      "Meat Products" => "肉制品",
      
      # Health Care 医疗保健
      "Pharmaceuticals" => "制药",
      "Biotechnology" => "生物技术",
      "Medical Devices" => "医疗器械",
      "Health Care Services" => "医疗保健服务",
      "Hospitals" => "医院",
      "Health Insurance" => "医疗保险",
      "Life Sciences Tools & Services" => "生命科学工具与服务",
      "Veterinary Services" => "兽医服务",
      
      # Financials 金融
      "Banks" => "银行",
      "Insurance" => "保险",
      "Asset Management" => "资产管理",
      "Investment Banking & Brokerage" => "投行与经纪",
      "Consumer Finance" => "消费金融",
      "Mortgage Finance" => "按揭金融",
      "Diversified Financial Services" => "综合金融服务",
      "Capital Markets" => "资本市场",
      
      # Information Technology 信息技术
      "Software" => "软件",
      "Software - Infrastructure" => "基础设施软件",
      "Software—Infrastructure" => "基础设施软件",
      "Software - Application" => "应用软件",
      "Software—Application" => "应用软件",
      "Semiconductors" => "半导体",
      "Hardware" => "硬件",
      "Computer Hardware" => "计算机硬件",
      "Consumer Electronics" => "消费电子",
      "Communication Equipment" => "通信设备",
      "IT Services" => "信息技术服务",
      "Internet Services" => "互联网服务",
      "Electronic Components" => "电子元器件",
      "Scientific & Technical Instruments" => "科学技术仪器",
      
      # Communication Services 通信服务
      "Telecom Services" => "电信服务",
      "Internet Content & Information" => "互联网内容与信息",
      "Media" => "媒体",
      "Entertainment" => "娱乐",
      "Interactive Media & Services" => "互动媒体与服务",
      "Publishing" => "出版",
      
      # Utilities 公用事业
      "Utilities - Regulated Electric" => "受监管电力",
      "Utilities - Regulated Gas" => "受监管燃气",
      "Utilities - Regulated Water" => "受监管水务",
      "Utilities - Renewable" => "可再生公用事业",
      "Utilities - Diversified" => "综合公用事业",
      
      # Real Estate 房地产
      "REIT - Diversified" => "多元化REIT",
      "REIT - Residential" => "住宅REIT",
      "REIT - Office" => "写字楼REIT",
      "REIT - Industrial" => "工业地产REIT",
      "REIT - Retail" => "商业地产REIT",
      "REIT - Healthcare Facilities" => "医疗地产REIT",
      "Real Estate Development" => "房地产开发",
      "Real Estate Services" => "房地产服务"
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