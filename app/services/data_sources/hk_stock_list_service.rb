module DataSources
  class HkStockListService
    # 麦蕊智数 - 港股列表基础信息
    MAIRUI_BASE_URL = "https://api.mairuiapi.com".freeze
    MAIRUI_LICENCE = ENV["MAIRUI_LICENCE"].presence || "LICENCE-66D8-9F96-0C7F0FBCD073"

    # 东方财富 - 港股公司资料（含行业分类）
    EM_DATACENTER_URL = "https://datacenter.eastmoney.com/securities/api/data/v1/get".freeze
    EM_REFERER = "https://emweb.securities.eastmoney.com/".freeze

    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    TIMEOUT = 15
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    # 请求间隔（秒），避免触发数据源限流
    REQUEST_INTERVAL = 0.3

    # 交易所映射
    EXCHANGE_MAPPING = {
      "HK" => "香港交易所"
    }.freeze

    # 恒生行业分类映射表（东方财富API原始名称 → HSICS标准一级/二级行业）
    # 数据来源：恒生行业映射.md（12个一级行业 + 31个二级行业）
    # 映射规则：
    #   1. 东方财富API返回的BELONG_INDUSTRY原始名称 → HSICS二级行业(industry)
    #   2. 通过二级行业反查一级行业(sector)
    #   3. 未映射到的名称和"其他"统一归入"其他"类别
    HK_INDUSTRY_MAPPING = {
      # ── 能源业 ──
      "石油及天然气" => { sector: "能源业", industry: "石油及天然气" },
      "煤炭"         => { sector: "能源业", industry: "煤炭" },

      # ── 原材料业 ──
      "采矿"               => { sector: "原材料业", industry: "采矿" },
      "一般金属及矿石"      => { sector: "原材料业", industry: "金属" },
      "黄金及贵金属"       => { sector: "原材料业", industry: "金属" },
      "有色金属"           => { sector: "原材料业", industry: "金属" },
      "原材料"             => { sector: "原材料业", industry: "基础原材料" },
      "建筑材料"           => { sector: "原材料业", industry: "基础原材料" },

      # ── 工业 ──
      "工业工程"           => { sector: "工业", industry: "工业工程" },
      "工用运输"           => { sector: "工业", industry: "工业运输" },
      "航运及港口"         => { sector: "工业", industry: "工业运输" },
      "交通设施"           => { sector: "工业", industry: "工业运输" },
      "航空服务"           => { sector: "工业", industry: "工业运输" },
      "支援服务"           => { sector: "工业", industry: "商业及专业服务" },
      "工用支援"           => { sector: "工业", industry: "商业及专业服务" },

      # ── 非必需性消费 ──
      "汽车"               => { sector: "非必需性消费", industry: "汽车" },
      "纺织及服饰"         => { sector: "非必需性消费", industry: "家庭用品及服饰" },
      "家庭电器及用品"     => { sector: "非必需性消费", industry: "家庭用品及服饰" },
      "媒体及娱乐"         => { sector: "非必需性消费", industry: "媒体及娱乐" },
      "旅游及消闲设施"     => { sector: "非必需性消费", industry: "媒体及娱乐" },
      "零售"               => { sector: "非必需性消费", industry: "零售" },
      "专业零售"           => { sector: "非必需性消费", industry: "零售" },
      "消费者主要零售商"   => { sector: "非必需性消费", industry: "零售" },

      # ── 必需性消费 ──
      "食物饮品"           => { sector: "必需性消费", industry: "食品、饮料及烟草" },
      "农业产品"           => { sector: "必需性消费", industry: "食品、饮料及烟草" },
      "个人及家庭用品"     => { sector: "必需性消费", industry: "个人及家庭用品" },

      # ── 医疗保健业 ──
      "药品及生物科技"     => { sector: "医疗保健业", industry: "制药、生物科技" },
      "其他医疗保健"       => { sector: "医疗保健业", industry: "医疗设备及服务" },

      # ── 电讯业 ──
      "电讯服务"           => { sector: "电讯业", industry: "电讯服务" },
      "电讯"               => { sector: "电讯业", industry: "电讯服务" },

      # ── 公用事业 ──
      "公用事业"           => { sector: "公用事业", industry: "公用事业" },

      # ── 金融业 ──
      "银行"               => { sector: "金融业", industry: "银行" },
      "保险"               => { sector: "金融业", industry: "保险" },
      "其他金融"           => { sector: "金融业", industry: "其他金融" },

      # ── 地产建筑业 ──
      "地产"               => { sector: "地产建筑业", industry: "地产发展" },
      "建筑"               => { sector: "地产建筑业", industry: "建筑" },

      # ── 资讯科技业 ──
      "软件服务"           => { sector: "资讯科技业", industry: "软件及服务" },
      "资讯科技器材"       => { sector: "资讯科技业", industry: "硬件及设备" },
      "半导体"             => { sector: "资讯科技业", industry: "硬件及设备" },
      "电子零件"           => { sector: "资讯科技业", industry: "硬件及设备" },

      # ── 综合企业 ──
      "综合企业"           => { sector: "综合企业", industry: "综合企业" },

      # ── 兜底 ──
      "其他"               => { sector: "其他", industry: "其他" }
    }.freeze

    # HSICS二级行业 → 一级行业 反查表（由HK_INDUSTRY_MAPPING自动生成）
    # 用于：给定已标准化的HSICS二级行业名，快速查出对应的一级行业
    INDUSTRY_TO_SECTOR = {}.tap do |lookup|
      HK_INDUSTRY_MAPPING.each_value do |v|
        lookup[v[:industry]] = v[:sector] unless lookup.key?(v[:industry])
      end
    end.freeze

    class << self
      # HTTP客户端，默认为Faraday，测试时可替换
      attr_writer :http_client

      def http_client
        @http_client || Faraday
      end

      def call(page: 1, size: nil)
        Rails.logger.info "=" * 70
        Rails.logger.info "开始爬取港股列表（麦蕊智数 + 东方财富）"
        Rails.logger.info "=" * 70

        stats = { total: 0, created: 0, updated: 0, skipped: 0, failed: 0, api_error: 0 }

        begin
          hk_list = fetch_hk_list_from_mairui
          if hk_list.empty?
            Rails.logger.warn "麦蕊智数返回空数据，使用测试数据..."
            hk_list = generate_test_data(size || 20)
          end

          stats[:total] = hk_list.size
          Rails.logger.info "共获取到 #{stats[:total]} 只港股基础信息"

          Rails.logger.info "开始补充行业分类信息..."
          puts "┌─────────────┬─────────────┬─────────────┬─────────────┬─────────────┐"
          puts "│    代码     │    名称     │  行业分类   │  交易所     │  处理状态   │"
          puts "├─────────────┼─────────────┼─────────────┼─────────────┼─────────────┤"

          hk_list.each_with_index do |item, index|
            begin
              # 从东方财富获取行业分类
              industry_info = fetch_hk_industry(item[:symbol])
              item[:sector] = industry_info[:sector]
              item[:industry] = industry_info[:industry]

              result = process_stock(item)
              stats[result] += 1

              status = case result
                       when :created then "新增"
                       when :updated then "更新"
                       when :skipped then "跳过"
                       else "失败"
                       end

              puts "│ #{item[:symbol]&.rjust(9)} │ #{item[:name].to_s[0..8]&.rjust(9)} │ #{item[:sector].to_s[0..8]&.rjust(9)} │ #{item[:exchange].to_s[0..8]&.rjust(9)} │ #{status&.rjust(9)} │"

              sleep REQUEST_INTERVAL
            rescue => e
              stats[:failed] += 1
              Rails.logger.error "处理港股 #{item[:symbol]} 失败: #{e.message}"
            end
          end

          puts "└─────────────┴─────────────┴─────────────┴─────────────┴─────────────┘"

        rescue => e
          Rails.logger.error "爬取过程异常: #{e.message}"
          Rails.logger.error e.backtrace.take(3).join("\n")
          stats[:api_error] += 1
        end

        Rails.logger.info "统计结果：总条数 #{stats[:total]}, 新增 #{stats[:created]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"
        Rails.logger.info "港股列表爬取完成"

        stats
      end

      private

      # 从麦蕊智数获取港股列表基础信息（代码、名称、交易所）
      def fetch_hk_list_from_mairui
        Rails.logger.info "正在从麦蕊智数获取港股列表..."
        url = "#{MAIRUI_BASE_URL}/hk/list/all/#{MAIRUI_LICENCE}"

        retries = RETRY_TIMES
        begin
          response = http_client.get(url) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.options.timeout = TIMEOUT
          end

          if response.success?
            raw_data = JSON.parse(response.body)
            unless raw_data.is_a?(Array)
              Rails.logger.warn "麦蕊智数返回格式异常: #{raw_data.class}"
              return []
            end

            Rails.logger.info "麦蕊智数返回 #{raw_data.size} 条港股"

            raw_data.filter_map do |item|
              begin
                dm = item["dm"]
                mc = item["mc"]
                jys = item["jys"]

                next unless dm.present? && mc.present?

                {
                  symbol: dm.strip,
                  name: mc.strip,
                  exchange: map_exchange(jys)
                }
              rescue => e
                Rails.logger.warn "跳过格式异常的港股数据: #{e.message}"
                nil
              end
            end
          else
            Rails.logger.error "麦蕊智数请求失败，状态码: #{response.status}"
            []
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries -= 1
          if retries > 0
            Rails.logger.warn "麦蕊智数请求超时/断连，重试中（剩余 #{retries} 次）..."
            sleep RETRY_INTERVAL
            retry
          end
          Rails.logger.error "麦蕊智数请求失败（已重试 #{RETRY_TIMES} 次）: #{e.message}"
          []
        rescue JSON::ParserError => e
          Rails.logger.error "麦蕊智数JSON解析失败: #{e.message}"
          []
        rescue => e
          Rails.logger.error "麦蕊智数请求异常: #{e.message}"
          []
        end
      end

      # 从东方财富获取港股行业分类信息，映射为HSICS标准一级/二级行业
      # 使用 datacenter.eastmoney.com 的 RPT_HKF10_INFO_ORGPROFILE 报表
      def fetch_hk_industry(symbol)
        retries = RETRY_TIMES

        begin
          response = http_client.get(EM_DATACENTER_URL) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = EM_REFERER
            req.params.merge!({
              reportName: "RPT_HKF10_INFO_ORGPROFILE",
              columns: "SECUCODE,SECURITY_CODE,ORG_NAME,BELONG_INDUSTRY",
              filter: %((SECUCODE="#{symbol}")),
              pageNumber: 1,
              pageSize: 200,
              sortTypes: "",
              sortColumns: "",
              source: "F10",
              client: "PC"
            })
            req.options.timeout = TIMEOUT
          end

          if response.success?
            data = JSON.parse(response.body)
            raw_industry = data.dig("result", "data", 0, "BELONG_INDUSTRY")

            if raw_industry.present?
              mapping = HK_INDUSTRY_MAPPING[raw_industry]
              if mapping
                { sector: mapping[:sector], industry: mapping[:industry] }
              else
                Rails.logger.warn "#{symbol} 行业名 '#{raw_industry}' 未在HK_INDUSTRY_MAPPING中，归入其他"
                { sector: "其他", industry: "其他" }
              end
            else
              { sector: "其他", industry: "其他" }
            end
          else
            Rails.logger.warn "#{symbol} 行业分类请求失败，状态码: #{response.status}"
            { sector: "其他", industry: "其他" }
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries -= 1
          if retries > 0
            Rails.logger.warn "#{symbol} 行业分类请求超时/断连，重试中（剩余 #{retries} 次）..."
            sleep RETRY_INTERVAL
            retry
          end
          Rails.logger.error "#{symbol} 行业分类请求失败（已重试 #{RETRY_TIMES} 次）: #{e.message}"
          { sector: "其他", industry: "其他" }
        rescue JSON::ParserError => e
          Rails.logger.error "#{symbol} 行业分类JSON解析失败: #{e.message}"
          { sector: "其他", industry: "其他" }
        rescue => e
          Rails.logger.error "#{symbol} 行业分类请求异常: #{e.message}"
          { sector: "其他", industry: "其他" }
        end
      end

      def map_exchange(jys_code)
        EXCHANGE_MAPPING[jys_code] || jys_code || "香港交易所"
      end

      # 处理单只港股：新增/更新/跳过，依据数据是否有变更
      def process_stock(item)
        symbol = item[:symbol]
        return :failed unless symbol.present?

        stock = Stock.find_or_initialize_by(symbol: symbol, market: "HK")
        is_new = stock.new_record?

        unless is_new
          no_changes = item[:name] == stock.name &&
                       item[:exchange] == stock.exchange &&
                       item[:sector] == stock.sector &&
                       item[:industry] == stock.industry
          return :skipped if no_changes
        end

        stock.name = item[:name]
        stock.exchange = item[:exchange]
        stock.sector = item[:sector]
        stock.industry = item[:industry]
        stock.status = "active" if stock.status.blank?
        stock.save!

        is_new ? :created : :updated
      rescue => e
        Rails.logger.error "处理港股 #{item[:symbol]} 失败: #{e.message}"
        :failed
      end

      # 生成测试数据（API不可用时的降级方案）
      def generate_test_data(size)
        Rails.logger.info "生成港股测试数据..."

        hk_samples = [
          { symbol: "00001.HK", name: "长和", exchange: "香港交易所", sector: "综合企业", industry: "综合企业" },
          { symbol: "00002.HK", name: "中电控股", exchange: "香港交易所", sector: "公用事业", industry: "公用事业" },
          { symbol: "00003.HK", name: "香港中华煤气", exchange: "香港交易所", sector: "公用事业", industry: "公用事业" },
          { symbol: "00005.HK", name: "汇丰控股", exchange: "香港交易所", sector: "金融业", industry: "银行" },
          { symbol: "00011.HK", name: "恒生银行", exchange: "香港交易所", sector: "金融业", industry: "银行" },
          { symbol: "00016.HK", name: "新鸿基地产", exchange: "香港交易所", sector: "地产建筑业", industry: "地产发展" },
          { symbol: "00027.HK", name: "银河娱乐", exchange: "香港交易所", sector: "非必需性消费", industry: "媒体及娱乐" },
          { symbol: "00066.HK", name: "港铁公司", exchange: "香港交易所", sector: "工业", industry: "工业运输" },
          { symbol: "00175.HK", name: "吉利汽车", exchange: "香港交易所", sector: "非必需性消费", industry: "汽车" },
          { symbol: "00241.HK", name: "阿里健康", exchange: "香港交易所", sector: "医疗保健业", industry: "医疗设备及服务" },
          { symbol: "00288.HK", name: "万洲国际", exchange: "香港交易所", sector: "必需性消费", industry: "食品、饮料及烟草" },
          { symbol: "00322.HK", name: "康师傅控股", exchange: "香港交易所", sector: "必需性消费", industry: "食品、饮料及烟草" },
          { symbol: "00388.HK", name: "香港交易所", exchange: "香港交易所", sector: "金融业", industry: "其他金融" },
          { symbol: "00700.HK", name: "腾讯控股", exchange: "香港交易所", sector: "资讯科技业", industry: "软件及服务" },
          { symbol: "00762.HK", name: "中国联通", exchange: "香港交易所", sector: "电讯业", industry: "电讯服务" },
          { symbol: "00883.HK", name: "中国海洋石油", exchange: "香港交易所", sector: "能源业", industry: "石油及天然气" },
          { symbol: "00941.HK", name: "中国移动", exchange: "香港交易所", sector: "电讯业", industry: "电讯服务" },
          { symbol: "00981.HK", name: "中芯国际", exchange: "香港交易所", sector: "资讯科技业", industry: "硬件及设备" },
          { symbol: "01211.HK", name: "比亚迪股份", exchange: "香港交易所", sector: "非必需性消费", industry: "汽车" },
          { symbol: "01299.HK", name: "友邦保险", exchange: "香港交易所", sector: "金融业", industry: "保险" },
          { symbol: "01398.HK", name: "工商银行", exchange: "香港交易所", sector: "金融业", industry: "银行" },
          { symbol: "01810.HK", name: "小米集团", exchange: "香港交易所", sector: "资讯科技业", industry: "硬件及设备" },
          { symbol: "02015.HK", name: "理想汽车", exchange: "香港交易所", sector: "非必需性消费", industry: "汽车" },
          { symbol: "02269.HK", name: "药明生物", exchange: "香港交易所", sector: "医疗保健业", industry: "制药、生物科技" },
          { symbol: "02318.HK", name: "中国平安", exchange: "香港交易所", sector: "金融业", industry: "保险" },
          { symbol: "02382.HK", name: "舜宇光学科技", exchange: "香港交易所", sector: "资讯科技业", industry: "硬件及设备" },
          { symbol: "02899.HK", name: "紫金矿业", exchange: "香港交易所", sector: "原材料业", industry: "金属" },
          { symbol: "03690.HK", name: "美团", exchange: "香港交易所", sector: "资讯科技业", industry: "软件及服务" },
          { symbol: "03988.HK", name: "中国银行", exchange: "香港交易所", sector: "金融业", industry: "银行" },
          { symbol: "09988.HK", name: "阿里巴巴", exchange: "香港交易所", sector: "非必需性消费", industry: "零售" }
        ]

        hk_samples.first([size.to_i, hk_samples.size].min).map do |stock|
          {
            symbol: stock[:symbol],
            name: stock[:name],
            exchange: stock[:exchange],
            sector: stock[:sector],
            industry: stock[:industry]
          }
        end
      end
    end
  end
end