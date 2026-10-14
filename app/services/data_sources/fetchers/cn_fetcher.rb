module DataSources
  module Fetchers
    class CnFetcher < BaseFetcher
      CN_DATA_URL = "https://datacenter-web.eastmoney.com/api/data/v1/get".freeze
      # 公告接口：北交所年报披露日的权威来源（F10 NOTICE_DATE 对北交所不可靠，
      # 实测会回填业绩快报/上市备案批量日期，2026-10-14 呆头儿报告核实）
      BJ_ANNOUNCE_URL = "https://np-anotice-stock.eastmoney.com/api/security/ann".freeze

      # 利润表字段映射：API列名 → 模型字段
      INCOME_FIELDS = {
        "TOTAL_OPERATE_INCOME" => :total_revenue,
        "OPERATE_COST"        => :operating_cost,
        "OPERATE_EXPENSE"     => :operating_expense,
        "SALE_EXPENSE"        => :selling_expense,
        "MANAGE_EXPENSE"      => :admin_expense,
        "FINANCE_EXPENSE"     => :interest_expense,
        "OPERATE_PROFIT"      => :operating_income,
        "TOTAL_PROFIT"        => :income_before_tax,
        "INCOME_TAX"          => :income_tax,
        "PARENT_NETPROFIT"    => :net_income_to_shareholders,
      }.freeze

      # 资产负债表字段映射：API列名 → 模型字段
      BALANCE_FIELDS = {
        "TOTAL_ASSETS"     => :total_assets,
        "TOTAL_LIABILITIES" => :total_liabilities,
        "TOTAL_EQUITY"     => :total_equity,
        "MONETARYFUNDS"    => :cash_and_cash_equivalents,
        "ACCOUNTS_RECE"    => :accounts_receivable,
        "INVENTORY"        => :inventory,
        "FIXED_ASSET"      => :property_plant_equipment,
      }.freeze

      # 现金流量表字段映射：API列名 → 模型字段
      CASHFLOW_FIELDS = {
        "NETCASH_OPERATE"  => :operating_cash_flow,
        "NETCASH_INVEST"   => :investing_cash_flow,
        "NETCASH_FINANCE"  => :financing_cash_flow,
        "CCE_ADD"          => :net_cash_change,
        "BEGIN_CCE"        => :beginning_cash,
        "END_CCE"          => :ending_cash,
      }.freeze

      # 财务指标字段映射：API列名 → 模型字段
      INDICATOR_FIELDS = {
        "BASIC_EPS"        => :basic_eps,
        "DEDUCT_BASIC_EPS" => :diluted_eps,
        "WEIGHTAVG_ROE"    => :roe_avg,
        "BPS"              => :nav_ps,
        "MGJYXJJE"         => :ncf_from_oa_ps,
        "XSMLL"            => :gross_margin,
      }.freeze

      REPORT_TYPE_CODE = "CN_ANNUAL".freeze

      def fetch_all(stock)
        symbol = stock.symbol
        market = stock.market
        secucode = symbol.sub(/^(SH|SZ|BJ)(.+)/, '\2.\1')

        results = []
        results << fetch_income(stock, secucode, market)
        results << fetch_balance(stock, secucode, market)
        results << fetch_cashflow(stock, secucode, market)
        results << fetch_indicator(stock, secucode, market)

        # F10 补充字段（扣非归母净利/扣非加权ROE/披露日期/稀释EPS）：
        # 只更新已存在的 FinancialIndicator 记录，成败不计入四表判定
        fetch_f10_supplement(stock, secucode, market)

        success_count = results.count { |r| r[:status] == :success }
        fail_count = results.count { |r| r[:status] == :failed }

        # 清理不在保留期次内的历史残留记录（历史抓取未记录期次，中报/季报被标成年报）
        periods = fetch_report_periods(secucode)
        cleanup_stale_records(stock, market, periods) if periods.any?

        # success: 是否有报表抓取失败；changed: 是否有报表数据新建/更新了记录
        { success: fail_count == 0, changed: success_count > 0 }
      end

      private

      # 获取全部报告期次（含季报），并按保留策略过滤
      # 返回 [{ report_date: Date, period_type: String }, ...]，按报告日期倒序
      def fetch_report_periods(secucode)
        params = {
          reportName: "RPT_DMSK_FN_INCOME",
          columns: "REPORT_DATE,DATE_TYPE_CODE",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "WEB", client: "WEB"
        }
        response = http_get(CN_DATA_URL, params: params)
        entries = cn_periods(extract_data_list(response), "REPORT_DATE")
        return [] if entries.empty?

        allowed = retention_period_set(entries)
        entries.select { |e| allowed.include?([ e[:period_type], e[:report_date] ]) }
               .uniq { |e| e[:report_date] }
               .sort_by { |e| e[:report_date] }
               .reverse
      rescue => e
        Rails.logger.error "[CnFetcher] #{secucode} 获取报告期次失败: #{e.message}"
        []
      end

      # 解析返回项的期次信息，返回 [{ report_date:, period_type: }, ...]
      def cn_periods(items, date_key)
        items.filter_map do |item|
          str = item[date_key].to_s.split(" ").first
          next if str.empty?
          date = Date.parse(str)
          { report_date: date, period_type: cn_period_type(item, date) }
        rescue ArgumentError
          nil
        end
      end

      # 期次判定：优先 DATE_TYPE_CODE（001年报/002中报/003一季报/004三季报）
      # 指标接口无该字段，按报告日期月日推导（A 股财年固定 12-31）
      def cn_period_type(item, date)
        case item["DATE_TYPE_CODE"].to_s
        when "001" then "annual"
        when "002" then "h1"
        when "003" then "q1"
        when "004" then "q3"
        else period_type_for_date(date)
        end
      end

      def fetch_income(stock, secucode, market)
        items = fetch_cn_data("RPT_DMSK_FN_INCOME", secucode)
        save_cn_income(stock, items, market, "income")
      end

      def fetch_balance(stock, secucode, market)
        items = fetch_cn_data("RPT_DMSK_FN_BALANCE", secucode)
        save_using_fields(stock, items, BalanceSheet, BALANCE_FIELDS, market, "balance")
      end

      def fetch_cashflow(stock, secucode, market)
        items = fetch_cn_data("RPT_DMSK_FN_CASHFLOW", secucode)
        save_using_fields(stock, items, CashFlow, CASHFLOW_FIELDS, market, "cashflow")
      end

      def fetch_indicator(stock, secucode, market)
        params = {
          reportName: "RPT_LICO_FN_CPD",
          columns: "REPORTDATE,BASIC_EPS,DEDUCT_BASIC_EPS,WEIGHTAVG_ROE,BPS,MGJYXJJE,XSMLL," \
                   "TOTAL_OPERATE_INCOME,PARENT_NETPROFIT",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORTDATE",
          source: "WEB", client: "WEB"
        }
        response = http_get(CN_DATA_URL, params: params)
        items = extract_data_list(response)
        save_indicator_items(stock, items, market, "indicator")
      end

      # F10 主要财务数据补充抓取：扣非归母净利润/扣非加权ROE/披露日期/稀释EPS
      # 按 (stock_id, report_date, market) 匹配已入库的 FinancialIndicator 并更新，
      # 记录不存在则跳过（不新建期次，保留策略由四表主流程控制）
      def fetch_f10_supplement(stock, secucode, market)
        params = {
          reportName: "RPT_F10_FINANCE_MAINFINADATA",
          columns: "SECUCODE,REPORT_DATE,NOTICE_DATE,KCFJCXSYJLR,ROEKCJQ,EPSXS",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "WEB", client: "WEB"
        }
        response = http_get(CN_DATA_URL, params: params)
        items = extract_data_list(response)
        unless items.any?
          log_progress(stock, "f10_supplement", :failed, "no data")
          return { status: :failed }
        end

        # 北交所年报披露日以公告接口为权威主源：F10 NOTICE_DATE 对北交所返回的
        # 疑似为业绩快报/上市备案批量日期（实测 4/4 出错，沪深 0 例外），不可信
        bj_annual = secucode.to_s.end_with?(".BJ")
        needed_years = bj_annual ? annual_report_years(items) : []
        notice_map = bj_annual ? fetch_annual_notice_dates(secucode, needed_years) : {}

        updated = 0
        gated = 0
        items.each do |item|
          date_str = item["REPORT_DATE"].to_s.split(" ").first
          next if date_str.empty?
          report_date = Date.parse(date_str)

          indicator = FinancialIndicator.find_by(stock_id: stock.id, report_date: report_date, market: market)
          next unless indicator

          f10_date = parse_notice_date(item["NOTICE_DATE"])
          disclosed = if bj_annual && report_date.month == 12
                        # 年报期次只认公告接口结果；查不到则留空，由消费侧公告兜底接管
                        notice_map[report_date.year]
                      else
                        f10_date if disclosed_at_valid?(f10_date, report_date, stock)
                      end
          gated += 1 if f10_date && disclosed.nil?

          data = {
            deducted_net_profit: parse_decimal(item["KCFJCXSYJLR"]),
            deducted_roe_weighted: parse_decimal(item["ROEKCJQ"]),
            eps_diluted: parse_decimal(item["EPSXS"]),
            disclosed_at: disclosed
          }
          next unless data.any? { |k, v| !v.nil? && indicator.send(k) != v }

          # compact：与上方「nil 不触发」的守卫同口径，源端某轮返回 null 不得抹掉已回填值
          indicator.update!(data.compact)
          updated += 1
        rescue ArgumentError
          next
        end

        status = updated > 0 ? :success : :skipped
        detail = [updated > 0 ? "#{updated} updated" : nil, gated > 0 ? "#{gated} gated" : nil].compact.join(", ")
        log_progress(stock, "f10_supplement", status, detail.presence)
        { status: status, count: updated, gated: gated }
      rescue => e
        log_progress(stock, "f10_supplement", :failed, e.message)
        { status: :failed, error: e.message }
      end

      # 披露日语义校验门：期次法定窗口（年报 6-30、中报 10-31、一季报 5-31、三季报 11-30 放宽）
      # 上市晚于窗口起点的次新/新三板转板股票，仅豁免「上市日之前」的披露（招股书/挂牌期合法日期），
      # 上市日之后的日期仍走窗口校验，防止荒谬值借豁免写入；
      # "窗口内的快报日期"拦不住，那类问题由北交所年报公告主源解决
      def disclosed_at_valid?(date, report_date, stock)
        return false if date.nil?
        y = report_date.year
        window = case report_date.month
                 when 12 then (Date.new(y + 1, 1, 1)..Date.new(y + 1, 6, 30))
                 when 6  then (Date.new(y, 7, 1)..Date.new(y, 10, 31))
                 when 3  then (Date.new(y, 4, 1)..Date.new(y, 5, 31))
                 when 9  then (Date.new(y, 10, 1)..Date.new(y, 11, 30))
                 end
        return true unless window
        return date <= stock.listing_date if stock.listing_date && stock.listing_date > window.begin
        window.cover?(date)
      end

      # items 中出现的年报期次年份集合（report_date 为 12-31）
      def annual_report_years(items)
        items.filter_map do |item|
          str = item["REPORT_DATE"].to_s.split(" ").first
          next if str.nil? || str.empty?
          d = (Date.parse(str) rescue nil)
          d.year if d && d.month == 12
        end.uniq
      end

      # 公告接口逐年年报公告日：{ 年份 => 最早公告日期 }
      # 标题匹配「YYYY年年度报告」，排除摘要/更正/编制提示等衍生公告；
      # 公告按日期倒序分页：needed_years 全部收集到即提前终止，
      # 否则翻到超出近 5 年范围或最多 6 页为止
      def fetch_annual_notice_dates(secucode, needed_years = [])
        code = secucode.to_s.split(".").first
        map = {}
        stop_before = Date.new(Date.current.year - 5, 1, 1)
        6.times do |page|
          response = http_get(BJ_ANNOUNCE_URL, params: {
            sr: -1, page_size: 100, page_index: page + 1, ann_type: "A",
            client_source: "web", stock_list: code, f_node: 0, s_node: 0
          })
          list = response.is_a?(Hash) ? response.dig("data", "list") : nil
          break unless list.is_a?(Array) && list.any?
          list.each do |ann|
            title = ann["title"].to_s
            m = title.match(/(\d{4})年年度报告/)
            next unless m
            next if title.match?(/摘要|更正|英文|制度|规则|细则|指引|说明会|预告|决议|披露|编制|提示性|专项说明|审议|议案/)
            date_str = ann["notice_date"].to_s.split(" ").first
            next if date_str.nil? || date_str.empty?
            d = Date.parse(date_str)
            year = m[1].to_i
            map[year] = d if map[year].nil? || d < map[year]
          rescue ArgumentError
            next
          end
          break if needed_years.any? && (needed_years - map.keys).empty?
          oldest = list.last["notice_date"].to_s.split(" ").first
          break if oldest.present? && Date.parse(oldest) < stop_before
        rescue ArgumentError
          next
        end
        map
      rescue => e
        Rails.logger.warn "[CnFetcher] #{secucode} 公告接口获取年报披露日失败: #{e.message}"
        {}
      end

      # NOTICE_DATE 形如 "2026-08-04 00:00:00"，取日期部分；空/异常返回 nil
      def parse_notice_date(value)
        str = value.to_s.split(" ").first
        return nil if str.nil? || str.empty?
        Date.parse(str)
      rescue ArgumentError
        nil
      end

      def fetch_cn_data(report_name, secucode)
        params = {
          reportName: report_name,
          columns: "ALL",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "WEB", client: "WEB"
        }
        response = http_get(CN_DATA_URL, params: params)
        extract_data_list(response)
      end

      def save_using_fields(stock, items, model_class, field_mapping, market, statement_name)
        unless items.any?
          log_progress(stock, statement_name, :failed, "no data")
          return { status: :failed }
        end
        allowed_periods = retention_period_set(cn_periods(items, "REPORT_DATE"))
        saved_count = 0
        skipped_count = 0
        items.each do |item|
          report_date_str = item["REPORT_DATE"].to_s.split(" ").first
          next if report_date_str.empty?
          report_date = Date.parse(report_date_str)
          period_type = cn_period_type(item, report_date)
          next unless allowed_periods.include?([ period_type, report_date ])
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )
          financial_data = {}
          field_mapping.each do |api_field, model_field|
            financial_data[model_field] = parse_decimal(item[api_field])
          end
          result = save_model_record(
            stock, financial_report, model_class, report_date, market, financial_data,
            period_type: period_type
          )
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end
        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} saved" : (skipped_count > 0 ? "#{skipped_count} skipped" : nil)
        log_progress(stock, statement_name, status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, statement_name, :failed, e.message)
        { status: :failed, error: e.message }
      end

      # 利润表：在基本字段映射基础上增加计算字段
      # - net_income (净利润) = TOTAL_PROFIT - INCOME_TAX
      # - gross_profit (毛利) = TOTAL_OPERATE_INCOME - OPERATE_COST
      # - operating_revenue = TOTAL_OPERATE_INCOME
      def save_cn_income(stock, items, market, statement_name)
        unless items.any?
          log_progress(stock, statement_name, :failed, "no data")
          return { status: :failed }
        end
        saved_count = 0
        skipped_count = 0
        allowed_periods = retention_period_set(cn_periods(items, "REPORT_DATE"))
        items.each do |item|
          report_date_str = item["REPORT_DATE"].to_s.split(" ").first
          next if report_date_str.empty?
          report_date = Date.parse(report_date_str)
          period_type = cn_period_type(item, report_date)
          next unless allowed_periods.include?([ period_type, report_date ])
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )
          financial_data = {}
          INCOME_FIELDS.each do |api_field, model_field|
            financial_data[model_field] = parse_decimal(item[api_field])
          end
          # 计算净利润 = 利润总额 - 所得税
          total_profit = parse_decimal(item["TOTAL_PROFIT"])
          income_tax = parse_decimal(item["INCOME_TAX"])
          if total_profit && income_tax
            financial_data[:net_income] = total_profit - income_tax
          end
          # 计算毛利 = 营业总收入 - 营业成本
          total_revenue_val = parse_decimal(item["TOTAL_OPERATE_INCOME"])
          operate_cost = parse_decimal(item["OPERATE_COST"])
          if total_revenue_val && operate_cost
            financial_data[:gross_profit] = total_revenue_val - operate_cost
          end
          # operating_revenue 与 total_revenue 取同一值
          financial_data[:operating_revenue] = financial_data[:total_revenue]
          result = save_model_record(
            stock, financial_report, IncomeStatement, report_date, market, financial_data,
            period_type: period_type
          )
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end
        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} saved" : (skipped_count > 0 ? "#{skipped_count} skipped" : nil)
        log_progress(stock, statement_name, status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, statement_name, :failed, e.message)
        { status: :failed, error: e.message }
      end

      def save_indicator_items(stock, items, market, statement_name)
        unless items.any?
          log_progress(stock, statement_name, :failed, "no data")
          return { status: :failed }
        end
        saved_count = 0
        skipped_count = 0
        allowed_periods = retention_period_set(cn_periods(items, "REPORTDATE"))
        items.each do |item|
          report_date_str = item["REPORTDATE"].to_s.split(" ").first
          next if report_date_str.empty?
          report_date = Date.parse(report_date_str)
          period_type = cn_period_type(item, report_date)
          next unless allowed_periods.include?([ period_type, report_date ])
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )
          financial_data = { report_type: REPORT_TYPE_CODE }
          INDICATOR_FIELDS.each do |api_field, model_field|
            financial_data[model_field] = parse_decimal(item[api_field])
          end

          # 净利率 = 归母净利润 / 营业总收入
          parent_netprofit = parse_decimal(item["PARENT_NETPROFIT"])
          total_revenue_val = parse_decimal(item["TOTAL_OPERATE_INCOME"])
          if parent_netprofit && total_revenue_val && total_revenue_val > 0
            financial_data[:net_sales_rate] = (parent_netprofit / total_revenue_val * 100).round(2)
          end

          # 总资产净利率(ROA) = 净利润 / 总资产
          # 资产负债率 = 总负债 / 总资产
          # 速动比率 = (流动资产 - 存货) / 流动负债
          # 以上指标均从已保存的 BalanceSheet + IncomeStatement 中获取
          balance_record = BalanceSheet.find_by(stock_id: stock.id, report_date: report_date, market: market)
          if balance_record
            # ROA
            if balance_record.total_assets && balance_record.total_assets > 0
              income_record = IncomeStatement.find_by(stock_id: stock.id, report_date: report_date, market: market)
              if income_record && income_record.net_income
                financial_data[:net_interest_of_ta] = (income_record.net_income / balance_record.total_assets * 100).round(2)
              end
            end

            # 资产负债率
            ta = balance_record.total_assets
            tl = balance_record.total_liabilities
            if ta && tl && ta > 0
              financial_data[:asset_liab_ratio] = (tl / ta * 100).round(2)
            end

            # 速动比率
            ca = balance_record.current_assets
            inv = balance_record.inventory
            cl = balance_record.current_liabilities
            if ca && inv && cl && cl > 0
              quick_assets = ca - inv
              financial_data[:quick_ratio] = (quick_assets / cl).round(2)
            end
          end

          result = save_model_record(
            stock, financial_report, FinancialIndicator, report_date, market, financial_data,
            period_type: period_type
          )
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end
        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} saved" : (skipped_count > 0 ? "#{skipped_count} skipped" : nil)
        log_progress(stock, statement_name, status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, statement_name, :failed, e.message)
        { status: :failed, error: e.message }
      end
    end
  end
end