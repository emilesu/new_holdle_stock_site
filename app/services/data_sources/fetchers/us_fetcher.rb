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

      # 期次类型文本 → period_type（东财部分报表直接给中文标准期次）
      # 资产负债表（RPT_USF10_FN_BALANCE）用「一季报/中报/三季报」而非「单季报/累计季报」，
      # 此时 REPORT 中的 Qn 不可按月数解析（如 2026/Q1 实为 3 个月），须优先按文本判定
      PERIOD_TYPE_BY_LABEL = { "一季报" => "q1", "中报" => "h1", "三季报" => "q3" }.freeze

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

        # Step 2: 获取全部报告期次（年报近 20 年 + 季报近 16 期）
        periods = fetch_report_periods(secucode)
        unless periods.any?
          log_progress(stock, "报告期次", :failed, "未获取到报告期次")
          return false
        end
        annual_count = periods.count { |p| p[:period_type] == "annual" }
        puts "  获取到 #{periods.size} 个报告期次（其中年报 #{annual_count} 期）"

        results = []
        results << fetch_and_save_report(stock, secucode, market, "RPT_USF10_FN_INCOME",
                                         IncomeStatement, INCOME_MAPPING, periods, "利润表")
        results << fetch_and_save_report(stock, secucode, market, "RPT_USF10_FN_BALANCE",
                                         BalanceSheet, BALANCE_MAPPING, periods, "资产负债表")
        results << fetch_and_save_report(stock, secucode, market, "RPT_USSK_FN_CASHFLOW",
                                         CashFlow, CASHFLOW_MAPPING, periods, "现金流量表")
        results << fetch_and_save_indicator(stock, secucode, market, periods)

        success_count = results.count { |r| r[:status] == :success }
        fail_count = results.count { |r| r[:status] == :failed }

        puts "  [#{stock.symbol}] 统计: 成功 #{success_count} 表, 失败 #{fail_count} 表"

        # 清理不在保留期次内的历史残留记录（历史抓取未记录期次，中报/季报被标成年报）
        cleanup_stale_records(stock, market, periods)

        # success: 是否有报表抓取失败；changed: 是否有报表数据新建/更新了记录
        { success: fail_count == 0, changed: success_count > 0 }
      end

      private

      # 通过查询组织信息获取美股 SECUCODE
      # 注意：东财 API 要求 SECURITY_CODE 不含点（如 BRK_B 而非 BRK.B）
      def resolve_secucode(symbol)
        # 将 BRK.B → BRK_B，东财 API 对含点代码不识别
        clean_symbol = symbol.tr('.', '_')

        params = {
          reportName: "RPT_USF10_INFO_ORGPROFILE",
          columns: "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR",
          filter: %((SECURITY_CODE="#{clean_symbol}")),
          source: "SECURITIES", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        data = extract_data_list(response)

        # 若转换后未找到，尝试原始符号（兼容普通不含点的代码）
        if data.empty? && clean_symbol != symbol
          params[:filter] = %((SECURITY_CODE="#{symbol}"))
          response = http_get(BASE_URL, params: params)
          data = extract_data_list(response)
        end

        data.first&.dig("SECUCODE")
      end

      # 获取美股全部报告期次（年报近 20 年 + 季报近 16 期）
      # 东财美股数据特点：
      #   - REPORT_TYPE = 年报 / 累计季报 / 单季报
      #   - REPORT = 期次标签（如 2025/FY、2026/Q9、2026/Q3）
      #   - 同一报告日期会同时返回「单季报」与「累计季报」两个变体，本系统统一采用累计口径
      #   - 财年结束日不固定（AAPL 9 月、MSFT 6 月），不能用 12-31 判定
      # 返回 [{ report_date: Date, period_type: String }, ...]，按报告日期倒序
      def fetch_report_periods(secucode)
        params = {
          reportName: "RPT_USF10_FN_INCOME",
          columns: "REPORT_DATE,REPORT,REPORT_TYPE",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 5000,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "SECURITIES", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        data = extract_data_list(response)
        return [] if data.empty?

        entries = data.filter_map do |item|
          date_str = item["REPORT_DATE"].to_s.split(" ").first
          next if date_str.empty?
          period_type = us_period_type(item["REPORT"], item["REPORT_TYPE"])
          next if period_type.nil?
          { report_date: Date.parse(date_str), period_type: period_type }
        rescue ArgumentError
          nil
        end

        allowed = retention_period_set(entries)
        entries.select { |e| allowed.include?([ e[:period_type], e[:report_date] ]) }
               .uniq { |e| e[:report_date] }
               .sort_by { |e| e[:report_date] }
               .reverse
      end

      # 美股期次判定
      # period_label: 期次标签（2025/FY、2026/Q9、2026/Q3）
      # type_label:   期次类型文本（年报 / 累计季报 / 单季报 / 一季报 / 中报 / 三季报）
      # 说明：累计季报的 Qn 中 n 即累计月数；单季报的 Qn 中 n 为财季序号（×3 = 月数），
      #       但只有 Q1（3 个月）本身属于累计口径，其余单季报变体一律排除
      def us_period_type(period_label, type_label)
        return nil if period_label.blank?
        return "annual" if type_label == "年报" || period_label.include?("FY")
        return PERIOD_TYPE_BY_LABEL[type_label] if PERIOD_TYPE_BY_LABEL.key?(type_label)

        n = period_label.to_s.split("/").last.to_s.delete("Q").to_i
        months = type_label == "单季报" ? n * 3 : n
        return nil if type_label == "单季报" && months != 3

        { 3 => "q1", 6 => "h1", 9 => "q3", 12 => "annual" }[months]
      end

      # 报告日期字符串 → period_type
      def period_type_map(periods)
        periods.each_with_object({}) { |p, h| h[p[:report_date].to_s] = p[:period_type] }
      end

      # 通用三大报表获取与保存
      # 注意：API可能返回同一报表日期同一科目的多条记录（不同合并层面），
      # 通过 dedup 逻辑优先选择年报(FY)合并数据
      # 注意：东财API不支持REPORT_DATE IN (...)过滤，需在代码层面过滤
      def fetch_and_save_report(stock, secucode, market, report_name,
                                model_class, field_mapping, periods, statement_name)
        params = {
          reportName: report_name,
          columns: "SECUCODE,REPORT_DATE,REPORT,REPORT_TYPE,STD_ITEM_CODE,AMOUNT,ITEM_NAME",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 5000,
          sortTypes: -1,
          sortColumns: "REPORT_DATE",
          source: "SECURITIES", client: "PC"
        }

        # 分页拉取（老牌公司历史数据行数可能超过单页上限）
        items = []
        page = 1
        loop do
          params[:pageNumber] = page
          response = http_get(BASE_URL, params: params)
          batch = extract_data_list(response)
          break if batch.empty?

          items.concat(batch)
          total_pages = response.dig("result", "pages").to_i
          break if total_pages <= page
          page += 1
        end

        unless items.any?
          log_progress(stock, statement_name, :failed, "API 无返回数据")
          return { status: :failed }
        end

        # 在代码层面过滤：仅保留保留期次内、且期次口径一致的记录
        # （同一日期会返回「单季报」与「累计季报」两个变体，只取累计口径的那一条）
        period_map = period_type_map(periods)
        items = items.select do |item|
          date_str = item["REPORT_DATE"].to_s.split(" ").first
          period_type = period_map[date_str]
          next false if period_type.nil?
          us_period_type(item["REPORT"], item["REPORT_TYPE"]) == period_type
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
          period_type = period_map[date_str]
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )

          financial_data = {}
          field_mapping.each do |cn_name, model_field|
            value = parse_decimal(field_values[cn_name]&.dig(:amount))
            financial_data[model_field] = value if value
          end

          # 处理净值字段：若股东权益合计缺失则用 总资产 - 总负债 推算
          if model_class == BalanceSheet && financial_data[:total_equity].nil?
            total_assets = financial_data[:total_assets]
            total_liabilities = financial_data[:total_liabilities]
            financial_data[:total_equity] = (total_assets && total_liabilities ? total_assets - total_liabilities : nil)
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
        detail = saved_count > 0 ? "#{saved_count} 条" : (skipped_count > 0 ? "已存在 #{skipped_count} 条" : nil)
        log_progress(stock, statement_name, status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, statement_name, :failed, e.message)
        { status: :failed, error: e.message }
      end

      # 美股财务指标
      # 注意：API 的期次字段与其他报表相反——DATE_TYPE 为期次类型文本，REPORT_TYPE 为期次标签
      # 注意：API可能返回同一DATE多条记录（不同合并层面），
      # 通过按日期分组后取 BASIC_EPS 最大的记录（合并报表级别 > 分部级别）
      def fetch_and_save_indicator(stock, secucode, market, periods)
        params = {
          reportName: "RPT_USF10_FN_GMAININDICATOR",
          columns: "SECUCODE,REPORT_DATE,DATE_TYPE,REPORT_TYPE,BASIC_EPS,DILUTED_EPS,ROE_AVG,ROA," \
                   "GROSS_PROFIT_RATIO,NET_PROFIT_RATIO,CURRENT_RATIO,SPEED_RATIO,DEBT_ASSET_RATIO",
          filter: %((SECUCODE="#{secucode}")),
          pageNumber: 1, pageSize: 1000,
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

        period_map = period_type_map(periods)

        # 按日期分组，仅保留保留期次内、且口径一致的记录
        grouped = {}
        items.each do |item|
          report_date_str = item["REPORT_DATE"].to_s.split(" ").first
          next unless report_date_str.present?
          period_type = period_map[report_date_str]
          next if period_type.nil?
          next unless us_period_type(item["REPORT_TYPE"], item["DATE_TYPE"]) == period_type

          basic_eps = parse_decimal(item["BASIC_EPS"]) || BigDecimal("0")
          abs_eps = basic_eps.abs

          if grouped[report_date_str].nil? || abs_eps > grouped[report_date_str][:abs_eps]
            grouped[report_date_str] = { item: item, abs_eps: abs_eps }
          end
        end

        saved_count = 0
        skipped_count = 0
        grouped.each do |report_date_str, entry|
          next unless entry[:item]
          item = entry[:item]
          report_date = Date.parse(report_date_str)
          period_type = period_map[report_date_str]

          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
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