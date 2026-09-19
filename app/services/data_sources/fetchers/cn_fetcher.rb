module DataSources
  module Fetchers
    class CnFetcher < BaseFetcher
      CN_DATA_URL = "https://datacenter-web.eastmoney.com/api/data/v1/get".freeze

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