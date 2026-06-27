module DataSources
  module Fetchers
    # 美股财务数据抓取器（东方财富数据源）
    # 使用 datacenter.eastmoney.com/securities/api/data/v1/get
    # 报表名: RPT_USF10_FN_INCOME / RPT_USF10_FN_BALANCE / RPT_USSK_FN_CASHFLOW
    #
    # 注意：API返回数据为分解格式（每行一个STD_ITEM_CODE+AMOUNT），
    #   同一报表日期可能存在多条同科目数据（不同合并层面或分部），
    #   需通过去重逻辑优先选择年报(FY)层面的合并数据。
    class UsFetcher < BaseFetcher
      # 利润表科目映射（东方财富API返回中文ITEM_NAME → 模型字段）
      INCOME_MAPPING = {
        "营业收入"              => :total_revenue,
        "主营收入"              => :total_revenue,
        "收入总额"              => :total_revenue,   # MKTX 等美股用此名称
        "营业成本"              => :operating_cost,
        "主营成本"              => :operating_cost,
        "毛利"                  => :gross_profit,
        "营业费用"              => :operating_expense,
        "营销费用"              => :selling_expense,
        "研发费用"              => :rd_expense,
        "一般及行政费用"         => :admin_expense,   # MKTX 等美股用此名称
        "营业利润"              => :operating_income,
        "经营溢利"              => :operating_income, # 港股风格命名
        "其他收入(支出)"        => :non_operating_income,
        "持续经营税前利润"      => :income_before_tax,
        "所得税"                => :income_tax,
        "净利润"                => :net_income,
        "持续经营净利润"        => :net_income,
        "归属于母公司股东净利润"  => :net_income_to_shareholders,
        "归属于普通股股东净利润"  => :net_income_to_shareholders,
        "基本每股收益-普通股"    => :basic_eps,
        "摊薄每股收益-普通股"    => :diluted_eps,
        "基本加权平均股数-普通股" => :weighted_avg_shares,
        "摊薄加权平均股数-普通股" => :diluted_avg_shares,
        "利息支出"              => :interest_expense,
      }.freeze

      # 资产负债表科目映射
      BALANCE_MAPPING = {
        "总资产"                     => :total_assets,
        "总负债"                     => :total_liabilities,
        "股东权益合计"               => :total_equity,
        "归属于母公司股东权益"       => :total_equity,
        "流动资产合计"               => :current_assets,
        "流动负债合计"               => :current_liabilities,
        "现金及现金等价物"           => :cash_and_cash_equivalents,
        "应收账款"                   => :accounts_receivable,
        "存货"                       => :inventory,
        "物业、厂房及设备"           => :property_plant_equipment,
        "固定资产"                   => :property_plant_equipment,  # 别名
        "长期负债"                   => :long_term_debt,
        "长期债务"                   => :long_term_debt,            # 别名
        "短期债务"                   => :short_term_debt,
        "留存收益"                   => :retained_earnings,
        "无形资产"                   => :intangible_assets,
        "商誉"                       => :goodwill,
        "长期投资"                   => :investments,
        "其他投资"                   => :investments,              # 别名
        "其他应收款"                 => :other_current_assets,
        "预付款项及其他应收款"        => :other_current_assets,     # MKTX 用此名称
        "其他流动资产"               => :other_current_assets,
        "其他非流动资产"             => :other_non_current_assets,
        "其他流动负债"               => :other_current_liabilities,
        "应付帐款及其他应付款"        => :other_current_liabilities, # MKTX 用此名称
        "其他非流动负债"             => :other_non_current_liabilities,
        "负债其他项目"               => :other_non_current_liabilities, # 别名
        "普通股"                     => :common_stock,
        "库存股"                     => :treasury_stock,
        "股本溢价"                   => :additional_paid_in_capital,
        "少数股东权益"               => :non_controlling_interest,
      }.freeze

      # 现金流量表科目映射
      CASHFLOW_MAPPING = {
        "经营活动产生的现金流量净额"  => :operating_cash_flow,
        "投资活动产生的现金流量净额"  => :investing_cash_flow,
        "筹资活动产生的现金流量净额"  => :financing_cash_flow,
        "现金及现金等价物增加(减少)额" => :net_cash_change,
        "现金及现金等价物期初余额"    => :beginning_cash,
        "现金及现金等价物期末余额"    => :ending_cash,
      }.freeze

      REPORT_TYPE_CODE = "US_ANNUAL".freeze

      def fetch_all(stock)
        symbol = stock.symbol
        market = stock.market

        puts "\n#{'=' * 60}"
        puts "美股财务数据: #{stock.symbol}"
        puts "#{'=' * 60}"

        # Step 1: 获取美股 SECUCODE（如 AAPL → AAPL.O）
        secucode = resolve_secucode(symbol)
        unless secucode
          log_progress(stock, "SECUCODE", :failed, "无法解析美股代码")
          return false
        end
        puts "  SECUCODE: #{secucode}"

        # Step 2: 获取年报日期列表
        year_dates = fetch_annual_report_dates(secucode)
        unless year_dates.any?
          log_progress(stock, "年报日期", :failed, "未获取到年报日期")
          return false
        end
        puts "  获取到 #{year_dates.size} 个年报日期"

        results = []
        results << fetch_and_save_report(stock, secucode, market, "RPT_USF10_FN_INCOME",
                                         IncomeStatement, INCOME_MAPPING, year_dates, "利润表")
        results << fetch_and_save_report(stock, secucode, market, "RPT_USF10_FN_BALANCE",
                                         BalanceSheet, BALANCE_MAPPING, year_dates, "资产负债表")
        results << fetch_and_save_report(stock, secucode, market, "RPT_USSK_FN_CASHFLOW",
                                         CashFlow, CASHFLOW_MAPPING, year_dates, "现金流量表")
        results << fetch_and_save_indicator(stock, secucode, market, year_dates)

        success_count = results.count { |r| r[:status] == :success }
        fail_count = results.count { |r| r[:status] == :failed }

        puts "  [#{stock.symbol}] 统计: 成功 #{success_count} 表, 失败 #{fail_count} 表"
        fail_count == 0
      end

      private

      # 通过查询组织信息获取美股 SECUCODE
      def resolve_secucode(symbol)
        params = {
          reportName: "RPT_USF10_INFO_ORGPROFILE",
          columns: "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR",
          filter: %((SECURITY_CODE="#{symbol}")),
          source: "SECURITIES", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        data = extract_data_list(response)
        data.first&.dig("SECUCODE")
      end

      # 获取美股年报日期
      # 注意：美股公司财年结束日不一定是12月31日（如AAPL在9月，MSFT在6月）
      # 因此不能用 keep_annual_report_date?（硬编码12月31日）
      def fetch_annual_report_dates(secucode)
        params = {
          reportName: "RPT_USF10_FN_INCOME",
          columns: "REPORT_DATE,REPORT",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 5000,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "SECURITIES", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        data = extract_data_list(response)
        return [] if data.empty?

        cutoff_date = MAX_YEARS_BACK.years.ago.to_date

        # 只保留年报 (FY)，不限定12月31日
        data
          .select { |item| item["REPORT"]&.include?("FY") }
          .map { |item| item["REPORT_DATE"].to_s.split(" ").first }
          .select { |d| d.present? && Date.parse(d) >= cutoff_date }
          .uniq
          .sort
          .reverse
      end

      # 通用三大报表获取与保存
      # 注意：API可能返回同一报表日期同一科目的多条记录（不同合并层面），
      # 通过 dedup 逻辑优先选择年报(FY)合并数据
      # 注意：东财API不支持REPORT_DATE IN (...)过滤，需在代码层面过滤
      def fetch_and_save_report(stock, secucode, market, report_name,
                                model_class, field_mapping, year_dates, statement_name)
        params = {
          reportName: report_name,
          columns: "SECUCODE,REPORT_DATE,REPORT,STD_ITEM_CODE,AMOUNT,ITEM_NAME",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 5000,
          sortTypes: -1,
          sortColumns: "REPORT_DATE",
          source: "SECURITIES", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        items = extract_data_list(response)

        unless items.any?
          log_progress(stock, statement_name, :failed, "API 无返回数据")
          return { status: :failed }
        end

        # 在代码层面过滤：只保留年报日期范围的数据
        year_dates_set = year_dates.to_set
        items = items.select do |item|
          date_str = item["REPORT_DATE"].to_s.split(" ").first
          date_str.present? && year_dates_set.include?(date_str)
        end

        # 按(日期, ITEM_NAME)聚合，自动去重：
        #   同一日期同一ITEM_NAME有多个值时，优先选 REPORT 含"FY"的，
        #   若都含/都不含FY则选绝对值较大的（合并数据 > 分部数据）
        grouped = {}
        items.each do |item|
          date = item["REPORT_DATE"].to_s.split(" ").first
          next unless date.present?

          item_name = item["ITEM_NAME"]
          next unless item_name.present? && field_mapping.key?(item_name)

          report = item["REPORT"] || ""
          amount = item["AMOUNT"]
          abs_amount = amount.to_s.to_f.abs

          grouped[date] ||= {}

          if grouped[date][item_name].nil?
            grouped[date][item_name] = { amount: amount, report: report }
          else
            existing = grouped[date][item_name]
            existing_is_fy = existing[:report].include?("FY")
            current_is_fy = report.include?("FY")

            # 优先级：FY > 非FY；同级别选绝对值大的
            if current_is_fy && !existing_is_fy
              grouped[date][item_name] = { amount: amount, report: report }
            elsif current_is_fy == existing_is_fy && abs_amount > existing[:amount].to_s.to_f.abs
              grouped[date][item_name] = { amount: amount, report: report }
            end
          end
        end

        saved_count = 0
        skipped_count = 0
        grouped.each do |date_str, field_values|
          report_date = Date.parse(date_str)
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market
          )

          financial_data = {}
          field_mapping.each do |cn_name, model_field|
            financial_data[model_field] = parse_decimal(field_values[cn_name]&.dig(:amount))
          end

          # 处理净值字段：若股东权益合计缺失则用 总资产 - 总负债 推算
          if model_class == BalanceSheet && financial_data[:total_equity].nil?
            total_assets = financial_data[:total_assets]
            total_liabilities = financial_data[:total_liabilities]
            financial_data[:total_equity] = (total_assets && total_liabilities ? total_assets - total_liabilities : nil)
          end

          result = save_model_record(
            stock, financial_report, model_class, report_date, market, financial_data
          )
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end

        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} 条" : (skipped_count > 0 ? "已存在 #{skipped_count} 条" : nil)
        log_progress(stock, statement_name, status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, statement_name, :failed, e.message)
        { status: :failed, error: e.message }
      end

      # 美股财务指标
      # 注意：API可能返回同一DATE多条记录（不同合并层面），
      # 通过按日期分组后取 BASIC_EPS 最大的记录（合并报表级别 > 分部级别）
      def fetch_and_save_indicator(stock, secucode, market, year_dates)
        params = {
          reportName: "RPT_USF10_FN_GMAININDICATOR",
          columns: "SECUCODE,REPORT_DATE,BASIC_EPS,DILUTED_EPS,ROE_AVG,ROA," \
                   "GROSS_PROFIT_RATIO,NET_PROFIT_RATIO,CURRENT_RATIO,SPEED_RATIO,DEBT_ASSET_RATIO",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "SECURITIES", client: "PC"
        }
        response = http_get(BASE_URL, params: params)
        items = extract_data_list(response)
        unless items.any?
          params[:reportName] = "RPT_USF10_FN_IMAININDICATOR"
          response = http_get(BASE_URL, params: params)
          items = extract_data_list(response)
        end
        unless items.any?
          log_progress(stock, "财务指标", :failed, "API 无返回数据")
          return { status: :failed }
        end

        cutoff_date = MAX_YEARS_BACK.years.ago.to_date

        # 按日期分组，每天取 BASIC_EPS 最大的记录（合并报表级别）
        grouped = {}
        items.each do |item|
          report_date_str = item["REPORT_DATE"].to_s.split(" ").first
          next unless report_date_str.present?
          report_date = Date.parse(report_date_str) rescue next
          next if report_date < cutoff_date
          next if year_dates.any? && !year_dates.include?(report_date_str)

          basic_eps = parse_decimal(item["BASIC_EPS"]) || BigDecimal("0")
          grouped[report_date_str] ||= { item: nil, max_eps: BigDecimal("-1") }
          if basic_eps > grouped[report_date_str][:max_eps]
            grouped[report_date_str] = { item: item, max_eps: basic_eps }
          end
        end

        saved_count = 0
        skipped_count = 0
        grouped.each do |report_date_str, entry|
          next unless entry[:item]
          item = entry[:item]
          report_date = Date.parse(report_date_str)

          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market
          )
          financial_data = {
            report_type: REPORT_TYPE_CODE,
            basic_eps: parse_decimal(item["BASIC_EPS"]),
            diluted_eps: parse_decimal(item["DILUTED_EPS"]),
            roe_avg: parse_decimal(item["ROE_AVG"]),
            net_interest_of_ta: parse_decimal(item["ROA"]),
            gross_margin: parse_decimal(item["GROSS_PROFIT_RATIO"]),
            net_sales_rate: parse_decimal(item["NET_PROFIT_RATIO"]),
            current_ratio: parse_decimal(item["CURRENT_RATIO"]),
            quick_ratio: parse_decimal(item["SPEED_RATIO"]),
            asset_liab_ratio: parse_decimal(item["DEBT_ASSET_RATIO"]),
          }
          result = save_model_record(stock, financial_report, FinancialIndicator, report_date, market, financial_data)
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end

        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} 条" : (skipped_count > 0 ? "已存在 #{skipped_count} 条" : nil)
        log_progress(stock, "财务指标", status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, "财务指标", :failed, e.message)
        { status: :failed, error: e.message }
      end
    end
  end
end