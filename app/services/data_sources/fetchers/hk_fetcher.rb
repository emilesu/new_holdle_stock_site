module DataSources
  module Fetchers
    # 港股财务数据抓取器（东方财富数据源）
    # 使用 datacenter.eastmoney.com/securities/api/data/v1/get
    # 报表名: RPT_HKF10_FN_INCOME_PC / RPT_HKF10_FN_BALANCE_PC / RPT_HKF10_FN_CASHFLOW_PC
    # 财务指标: stock_financial_hk_analysis_indicator_em (AKShare 封装)
    #
    # 数据格式：按 STD_ITEM_NAME（科目）行返回，需按 REPORT_DATE 聚合成一条记录
    class HkFetcher < BaseFetcher
      # 港股四张报表的 API 配置
      STATEMENT_CONFIG = {
        income:    { report_name: "RPT_HKF10_FN_INCOME_PC",    model: IncomeStatement },
        balance:   { report_name: "RPT_HKF10_FN_BALANCE_PC",   model: BalanceSheet },
        cashflow:  { report_name: "RPT_HKF10_FN_CASHFLOW_PC",  model: CashFlow },
        indicator: { report_name: nil, model: FinancialIndicator }
      }.freeze

      # 利润表：中文科目名 → 模型字段名
      INCOME_MAPPING = {
        "营业额"           => :total_revenue,
        "毛利"             => :gross_profit,
        "经营溢利"         => :operating_income,
        "除税前溢利"       => :income_before_tax,
        "税项"             => :income_tax,
        "除税后溢利"       => :net_income,
        "股东应占溢利"     => :net_income_to_shareholders,
        "每股基本盈利"     => :basic_eps,
        "每股摊薄盈利"     => :diluted_eps,
        "销售及分销费用"   => :selling_expense,
        "行政开支"         => :admin_expense,
        "融资成本"         => :interest_expense,
        "其他营业收入"     => :non_operating_income,
        "其他收益"         => :non_operating_income,
        "营运支出"         => :operating_cost,
        "研发费用"         => :rd_expense,
        "利息收入"         => :non_operating_income,
      }.freeze

      # 资产负债表：中文科目名 → 模型字段名
      BALANCE_MAPPING = {
        "总资产"                   => :total_assets,
        "总负债"                   => :total_liabilities,
        "净资产"                   => :total_equity,
        "流动资产合计"             => :current_assets,
        "流动负债合计"             => :current_liabilities,
        "现金及等价物"             => :cash_and_cash_equivalents,
        "应收帐款"                 => :accounts_receivable,
        "贸易及其他应收款项"       => :accounts_receivable,
        "贸易及其他应收款"         => :accounts_receivable,
        "应收账款"                => :accounts_receivable,
        "预付款按金及其他应收款"   => :accounts_receivable,
        "存货"                     => :inventory,
        "物业厂房及设备"           => :property_plant_equipment,
        "固定资产"                 => :property_plant_equipment,  # 别名
        "无形资产"                 => :intangible_assets,
        "商誉"                     => :goodwill,
        "短期贷款"                 => :short_term_debt,
        "长期贷款"                 => :long_term_debt,
        "股本"                     => :common_stock,
        "股本溢价"                 => :additional_paid_in_capital,
        "库存股"                   => :treasury_stock,
        "少数股东权益"             => :non_controlling_interest,
        "保留溢利(累计亏损)"       => :retained_earnings,
        "其他储备"                 => :retained_earnings,
      }.freeze

      # 现金流量表：中文科目名 → 模型字段名
      CASHFLOW_MAPPING = {
        "经营业务现金净额" => :operating_cash_flow,
        "投资业务现金净额" => :investing_cash_flow,
        "融资业务现金净额" => :financing_cash_flow,
        "现金净额"        => :net_cash_change,
        "期初现金"        => :beginning_cash,
        "期末现金"        => :ending_cash,
      }.freeze

      REPORT_TYPE_CODE = "HK_ANNUAL".freeze

      # 现金流量汇总表的 REPORT_TYPE 文本 → period_type（累计口径）
      REPORT_TYPE_MAP = {
        "年报" => "annual",
        "三季报" => "q3",
        "中报" => "h1",
        "一季报" => "q1"
      }.freeze

      # 东财 DATE_TYPE_CODE → period_type（与 A 股口径一致）
      DATE_TYPE_MAP = { "001" => "annual", "002" => "h1", "003" => "q1", "004" => "q3" }.freeze

      def fetch_all(stock)
        symbol = stock.symbol.sub(/\.\w+$/, "")  # 移除后缀：00700.HK → 00700
        market = stock.market
        puts "\n#{'=' * 60}"
        puts "📊 港股财务数据: #{stock.symbol} | #{stock.name}"
        puts "#{'=' * 60}"

        # Step 1: 获取全部报告期次（年报近 20 年 + 季报近 16 期）
        periods = fetch_report_periods(symbol)
        unless periods.any?
          log_progress(stock, "报告期次", :failed, "未获取到报告期次")
          return false
        end
        annual_count = periods.count { |p| p[:period_type] == "annual" }
        puts "  📅 获取到 #{periods.size} 个报告期次（其中年报 #{annual_count} 期）"

        results = []
        results << fetch_and_save_income(stock, symbol, market, periods)
        results << fetch_and_save_balance(stock, symbol, market, periods)
        results << fetch_and_save_cashflow(stock, symbol, market, periods)
        results << fetch_and_save_indicator(stock, symbol, market, periods)

        success_count = results.count { |r| r[:status] == :success }
        fail_count = results.count { |r| r[:status] == :failed }

        puts "\n  📊 [#{stock.symbol}] 统计: 成功 #{success_count} 表, 失败 #{fail_count} 表"

        # 清理不在保留期次内的历史残留记录（历史抓取曾把中报当成年报入库）
        cleanup_stale_records(stock, market, periods)

        # success: 是否有报表抓取失败；changed: 是否有报表数据新建/更新了记录
        { success: fail_count == 0, changed: success_count > 0 }
      end

      private

      # 获取全部报告期次（含季报），并按保留策略过滤
      # 主数据源: RPT_CUSTOM_HKSK_APPFN_CASHFLOW_SUMMARY（REPORT_LIST 内含全部期次，无需分页）
      # 备选数据源: RPT_HKF10_FN_INCOME_PC（需分页，按 DATE_TYPE_CODE 判期次）
      # 返回 [{ report_date: Date, period_type: String }, ...]，按报告日期倒序
      def fetch_report_periods(symbol)
        entries = fetch_periods_from_cashflow_summary(symbol)
        entries = fetch_periods_from_income_pc(symbol) if entries.empty?
        return [] if entries.empty?

        allowed = retention_period_set(entries)
        entries.select { |e| allowed.include?([ e[:period_type], e[:report_date] ]) }
               .uniq { |e| e[:report_date] }
               .sort_by { |e| e[:report_date] }
               .reverse
      end

      # 从现金流量汇总表获取全部报告期次（主流港股，含非 12 月财年）
      def fetch_periods_from_cashflow_summary(symbol)
        params = {
          reportName: "RPT_CUSTOM_HKSK_APPFN_CASHFLOW_SUMMARY",
          columns: "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR,START_DATE,REPORT_DATE,FISCAL_YEAR,REPORT_TYPE",
          filter: %((SECUCODE="#{symbol}.HK")),
          source: "F10", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        data = extract_data_list(response)
        return [] if data.empty?

        report_list = data.first["REPORT_LIST"] || []
        report_list.filter_map do |r|
          period_type = REPORT_TYPE_MAP[r["REPORT_TYPE"].to_s]
          date_str = r["REPORT_DATE"].to_s.split(" ").first
          next if period_type.nil? || date_str.empty?
          { report_date: Date.parse(date_str), period_type: period_type }
        rescue ArgumentError
          nil
        end
      rescue
        []
      end

      # 备选：从利润表全量数据获取报告期次（分页拉取，按 DATE_TYPE_CODE 判期次）
      def fetch_periods_from_income_pc(symbol)
        entries = []
        page = 1
        loop do
          params = {
            reportName: "RPT_HKF10_FN_INCOME_PC",
            columns: "SECUCODE,REPORT_DATE,DATE_TYPE_CODE,FISCAL_YEAR",
            filter: %((SECUCODE="#{symbol}.HK")),
            pageNumber: page, pageSize: 500,
            sortTypes: -1, sortColumns: "REPORT_DATE",
            source: "F10", client: "PC"
          }
          response = http_get(BASE_URL, params: params)
          items = extract_data_list(response)
          break if items.empty?

          items.each do |item|
            date_str = item["REPORT_DATE"].to_s.split(" ").first
            next if date_str.empty?
            begin
              date = Date.parse(date_str)
            rescue ArgumentError
              next
            end
            period_type = DATE_TYPE_MAP[item["DATE_TYPE_CODE"].to_s] || period_type_for_date(date)
            entries << { report_date: date, period_type: period_type }
          end

          total_pages = response.dig("result", "pages").to_i
          break if total_pages <= page
          page += 1
        end
        entries
      rescue
        []
      end

      # 期次日期字符串集合（用于报表请求过滤与保存判定）
      def period_date_strings(periods)
        periods.map { |p| p[:report_date].to_s }
      end

      # 报告日期字符串 → period_type
      def period_type_map(periods)
        periods.each_with_object({}) { |p, h| h[p[:report_date].to_s] = p[:period_type] }
      end

      # === 利润表 ===
      def fetch_and_save_income(stock, symbol, market, periods)
        items = fetch_statement(symbol, "RPT_HKF10_FN_INCOME_PC", period_date_strings(periods))
        unless items.any?
          log_progress(stock, "利润表", :failed, "API 无返回数据")
          return { status: :failed }
        end

        # 按 REPORT_DATE 聚合科目
        grouped = group_items_by_date(items, INCOME_MAPPING.keys)
        period_map = period_type_map(periods)

        saved_count = 0
        skipped_count = 0
        grouped.each do |date_str, field_values|
          period_type = period_map[date_str]
          next if period_type.nil?
          report_date = Date.parse(date_str)
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )

          financial_data = {}
          INCOME_MAPPING.each do |cn_name, model_field|
            value = parse_decimal(field_values[cn_name])
            financial_data[model_field] = value if value
          end

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
        detail = saved_count > 0 ? "#{saved_count} 条" : (skipped_count > 0 ? "已存在 #{skipped_count} 条" : nil)
        log_progress(stock, "利润表", status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, "利润表", :failed, e.message)
        { status: :failed, error: e.message }
      end

      # === 资产负债表 ===
      def fetch_and_save_balance(stock, symbol, market, periods)
        items = fetch_statement(symbol, "RPT_HKF10_FN_BALANCE_PC", period_date_strings(periods))
        unless items.any?
          log_progress(stock, "资产负债表", :failed, "API 无返回数据")
          return { status: :failed }
        end

        grouped = group_items_by_date(items, BALANCE_MAPPING.keys)
        period_map = period_type_map(periods)

        saved_count = 0
        skipped_count = 0
        grouped.each do |date_str, field_values|
          period_type = period_map[date_str]
          next if period_type.nil?
          report_date = Date.parse(date_str)
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )

          financial_data = {}
          BALANCE_MAPPING.each do |cn_name, model_field|
            value = parse_decimal(field_values[cn_name])
            financial_data[model_field] = value if value
          end

          # 若 API 未返回净资产，用总资产 - 总负债 推算
          if financial_data[:total_equity].nil?
            ta = financial_data[:total_assets]
            tl = financial_data[:total_liabilities]
            financial_data[:total_equity] = (ta && tl ? ta - tl : nil)
          end

          result = save_model_record(
            stock, financial_report, BalanceSheet, report_date, market, financial_data,
            period_type: period_type
          )
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end

        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} 条" : (skipped_count > 0 ? "已存在 #{skipped_count} 条" : nil)
        log_progress(stock, "资产负债表", status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, "资产负债表", :failed, e.message)
        { status: :failed, error: e.message }
      end

      # === 现金流量表 ===
      def fetch_and_save_cashflow(stock, symbol, market, periods)
        items = fetch_statement(symbol, "RPT_HKF10_FN_CASHFLOW_PC", period_date_strings(periods))
        unless items.any?
          log_progress(stock, "现金流量表", :failed, "API 无返回数据")
          return { status: :failed }
        end

        grouped = group_items_by_date(items, CASHFLOW_MAPPING.keys)
        period_map = period_type_map(periods)

        saved_count = 0
        skipped_count = 0
        grouped.each do |date_str, field_values|
          period_type = period_map[date_str]
          next if period_type.nil?
          report_date = Date.parse(date_str)
          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )

          financial_data = {}
          CASHFLOW_MAPPING.each do |cn_name, model_field|
            value = parse_decimal(field_values[cn_name])
            financial_data[model_field] = value if value
          end

          # 若 API 未返回现金净额，用 经营+投资+融资 推算
          if financial_data[:net_cash_change].nil?
            oc = financial_data[:operating_cash_flow]
            ic = financial_data[:investing_cash_flow]
            fc = financial_data[:financing_cash_flow]
            if oc && ic && fc
              net = (oc + ic + fc).to_d
              financial_data[:net_cash_change] = net == 0 ? nil : net
            end
          end

          result = save_model_record(
            stock, financial_report, CashFlow, report_date, market, financial_data,
            period_type: period_type
          )
          case result
          when :success then saved_count += 1
          when :skipped then skipped_count += 1
          end
        end

        status = saved_count > 0 ? :success : (skipped_count > 0 ? :skipped : :failed)
        detail = saved_count > 0 ? "#{saved_count} 条" : (skipped_count > 0 ? "已存在 #{skipped_count} 条" : nil)
        log_progress(stock, "现金流量表", status, detail)
        { status: status, count: saved_count }
      rescue => e
        log_progress(stock, "现金流量表", :failed, e.message)
        { status: :failed, error: e.message }
      end

      # === 财务指标 ===
      def fetch_and_save_indicator(stock, symbol, market, periods)
        # API请求间隔，避免频率限制
        sleep 0.3

        # 三级降级策略：
        # 1. GMAININDICATOR（全字段）
        # 2. MAININDICATOR（全字段，部分港股不支持）
        # 3. MAININDICATOR（精简字段，仅 BASIC_EPS + ROE_AVG，00005.HK/00388.HK等可用）
        items = fetch_indicator_from_api("RPT_HKF10_FN_GMAININDICATOR", symbol)
        if items.empty?
          items = fetch_indicator_from_api("RPT_HKF10_FN_MAININDICATOR", symbol)
        end
        if items.empty?
          items = fetch_indicator_from_api_limited("RPT_HKF10_FN_MAININDICATOR", symbol)
        end

        unless items.any?
          log_progress(stock, "财务指标", :failed, "API 无返回数据")
          return { status: :failed }
        end

        period_map = period_type_map(periods)

        saved_count = 0
        skipped_count = 0
        items.each do |item|
          report_date_str = item["REPORT_DATE"].to_s.split(" ").first
          next unless report_date_str.present?

          report_date = Date.parse(report_date_str) rescue next
          # 港股财年结束日不固定（腾讯12-31，阿里03-31），仅保留 periods 中的期次
          period_type = period_map[report_date_str]
          next if period_type.nil?

          financial_report = find_or_create_financial_report(
            stock, report_date: report_date, report_type: REPORT_TYPE_CODE, market: market,
            period_type: period_type
          )

          financial_data = {
            report_type: REPORT_TYPE_CODE,
            basic_eps: parse_decimal(item["BASIC_EPS"]),
            diluted_eps: parse_decimal(item["DILUTED_EPS"]),
            roe_avg: parse_decimal(item["ROE_AVG"]),
            nav_ps: parse_decimal(item["BPS"]),
            gross_margin: parse_decimal(item["GROSS_PROFIT_RATIO"]),
            net_interest_of_ta: parse_decimal(item["ROA"]),
            net_sales_rate: parse_decimal(item["NET_PROFIT_RATIO"]),
            asset_liab_ratio: parse_decimal(item["DEBT_ASSET_RATIO"]),
            current_ratio: parse_decimal(item["CURRENT_RATIO"]),
            quick_ratio: parse_decimal(item["SPEED_RATIO"]),
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

      # 调用财务指标API，返回数据列表
      # 注意：columns 中不能包含 FISCAL_YEAR 等API不支持的字段，否则报 code=9501
      def fetch_indicator_from_api(report_name, symbol)
        params = {
          reportName: report_name,
          columns: "SECUCODE,REPORT_DATE,BASIC_EPS," \
                   "DILUTED_EPS,ROE_AVG,BPS,GROSS_PROFIT_RATIO,ROA,NET_PROFIT_RATIO," \
                   "DEBT_ASSET_RATIO,CURRENT_RATIO,SPEED_RATIO",
          filter: %((SECUCODE="#{symbol}.HK")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "F10", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        items = extract_data_list(response)
        items.any? ? items : []
      rescue
        []
      end

      # 精简 columns 的财务指标 API 调用（用于 00005.HK/00388.HK 等）
      # MAININDICATOR 对部分港股仅支持 BASIC_EPS 和 ROE_AVG 等基础字段
      def fetch_indicator_from_api_limited(report_name, symbol)
        params = {
          reportName: report_name,
          columns: "SECUCODE,REPORT_DATE,BASIC_EPS,ROE_AVG",
          filter: %((SECUCODE="#{symbol}.HK")),
          pageNumber: 1, pageSize: 500,
          sortTypes: -1, sortColumns: "REPORT_DATE",
          source: "F10", client: "PC"
        }

        response = http_get(BASE_URL, params: params)
        items = extract_data_list(response)
        items.any? ? items : []
      rescue
        []
      end

      # === 通用方法 ===

      # 调用东财 API 获取某张报表的原始数据
      # 注意：东财接口不支持 `REPORT_DATE in (...)` 语法（会被静默忽略），只能用单值等值或范围过滤
      def fetch_statement(symbol, report_name, date_strings)
        return [] if date_strings.empty?

        min_date = date_strings.min
        items = []
        page = 1
        loop do
          params = {
            reportName: report_name,
            columns: "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR,REPORT_DATE,FISCAL_YEAR," \
                     "STD_ITEM_CODE,STD_ITEM_NAME,AMOUNT",
            filter: %((SECUCODE="#{symbol}.HK")(REPORT_DATE>='#{min_date}')),
            pageNumber: page, pageSize: 5000,
            sortTypes: -1,
            sortColumns: "REPORT_DATE",
            source: "F10", client: "PC"
          }

          response = http_get(BASE_URL, params: params)
          batch = extract_data_list(response)
          break if batch.empty?

          items.concat(batch)
          total_pages = response.dig("result", "pages").to_i
          break if total_pages <= page
          page += 1
        end
        items
      end

      # 按 REPORT_DATE 和科目名聚合数据
      # 输入: [{REPORT_DATE:, STD_ITEM_NAME:, AMOUNT:}, ...]
      # 输出: {"2025-12-31" => {"营业额" => 743689000000, ...}, ...}
      def group_items_by_date(items, target_subjects)
        grouped = {}
        items.each do |item|
          date = item["REPORT_DATE"].to_s.split(" ").first
          next unless date.present?

          subject = item["STD_ITEM_NAME"]
          next unless target_subjects.include?(subject)

          grouped[date] ||= {}
          grouped[date][subject] = item["AMOUNT"]
        end
        grouped
      end
    end
  end
end