module DataSources
  # 无杠杆ROE（Unlevered ROE）计算引擎，口径B
  # 公式：(归母净利润TTM + 税后净财务费用TTM) ÷ (归母净资产 + 有息负债) × 100
  #   有息负债 = 短期借款 + 长期借款 + 应付债券 + 一年内到期的非流动负债
  #   （v1 不含租赁负债；A股票据为经营性质不计。科目 NULL 按 0 参与求和）
  # 分子加回税后利息是口径B与口径A的本质区别：只扩分母、不加回分子，
  # 会把"剥掉杠杆垫高"变成"反向惩罚高负债公司"，破坏跨公司可比性。
  # 设计：compute 为纯函数（科目字典 → 值+flag+参考ROE），call 负责多期次
  # TTM 装配、落库与复核报警；采集增量与历史回填共用同一实现。
  class UnleveredRoeService
    FLAG_NORMAL = 0             # 正常
    FLAG_NOT_DISCLOSED = 1      # 未披露/数据不全（含未重爬新科目的历史期次）
    FLAG_NEGATIVE_EQUITY = 2    # 净资产≤0，指标无意义
    FLAG_FINANCIAL = 3          # 金融股（银行/券商/保险等）不适用，口径冻结直接剔除
    FLAG_INTEREST_MISSING = 4   # 美股有有息负债但利息费用未披露，按0加回（结果可能偏低）
    FLAG_DEBT_INCOMPLETE = 5    # REIT 有息负债数据不完整（东财未拆分），分母失真，直接隐藏
    FLAG_EXTREME = 6            # 美股 |无杠杆ROE|>100，分母过小，数值无展示意义

    # 复核报警阈值：显著高于期末口径 TTM ROE 参考值，或绝对值超出常识区间
    ALARM_ABOVE_ROE_PP = 10.0
    ALARM_ABS_LIMIT = 100.0

    # REIT 有息负债/总负债低于该比例时，判定为数据源未拆分债务。
    # 生产库债务率双峰：116 只 <20%、5 只 20-40%、2 只 40-50%，62 只 ≥50%；
    # AMT/PLD/SPG/LAMR 等拆分完整的 REIT 约 83-86%，50% 阈值可覆盖灰区且不误杀。
    US_REIT_MIN_DEBT_RATIO = 0.5

    # 非 REIT 通用债务缺口：有息负债为 0、总负债超过 2×归母权益且超过 5B，
    # 同时利息支出科目缺失（或债务为 0 但有非零利息），说明数据源漏掉了债务科目
    # （实测 VEON/GRFS/AFRM、COF/AXP 等信用服务放贷机构）。
    # 5B 门槛避免把 DNN 这类总负债很小的真无债务公司误杀。
    US_DEBT_GAP_MIN_LIABILITIES = 5_000_000_000
    US_DEBT_GAP_LIABILITY_MULTIPLE = 2.0

    # 非 REIT 部分债务缺口：利息费用/有息负债 > 20%（隐含利率异常）且总负债 > 1B，
    # 说明债务只抓到一部分（实测 RUN 3.0x、OPEN 0.7x、SIM 20.4x）。
    US_DEBT_GAP_MAX_IMPLIED_RATE = 0.2
    US_DEBT_GAP_MIN_LIABILITIES_FOR_RATE = 1_000_000_000

    # flag≠0 时前端悬浮原因（flag 1/2/3 值显示为 —；flag 4 保留数值并提示加回缺失）
    FLAG_REASONS = {
      FLAG_NOT_DISCLOSED => "财报科目未披露或尚未采集",
      FLAG_NEGATIVE_EQUITY => "归母净资产≤0，指标不适用",
      FLAG_FINANCIAL => "金融股（银行/券商/保险/资管等）不适用本指标",
      FLAG_INTEREST_MISSING => "利息费用未披露，未加回利息（结果可能偏低）",
      FLAG_DEBT_INCOMPLETE => "有息负债数据不完整（数据源未拆分）",
      FLAG_EXTREME => "数值极端（分母过小），不展示"
    }.freeze

    # 美股金融股行业关键词（中文映射 + 英文兜底）：以负债为经营原料的机构剔除；
    # 信用服务（V/MA 等支付网络）、金融数据与交易所保留，避免误伤经营型公司
    US_FINANCIAL_INDUSTRY = /银行|保险|寿险|财险|医保计划|资本市场|资产管理|金融综合|抵押金融|抵押REIT|壳公司|
                             Banks|Insurance|Healthcare\sPlans|Capital\sMarkets|Asset\sManagement|
                             Financial\sConglomerates|Mortgage\sFinance|Mortgage\sREIT|Shell\sCompanies/x

    # 加密矿企/加密资产运营公司：Yahoo 归入「资本市场」，但属经营型公司，不按金融股剔除
    US_CRYPTO_OPERATORS = %w[HUT CLSK MARA RIOT BITF CIFR IREN WULF CORZ BTBT].freeze

    def self.flag_reason(flag)
      FLAG_REASONS[flag]
    end

    class << self
      # 主入口：重算该股票全部期次并写回 financial_indicators
      def call(stock:, market: "CN")
        indicators = FinancialIndicator.where(stock_id: stock.id, market: market).to_a
        return { updated: 0 } if indicators.empty?

        incomes = IncomeStatement.where(stock_id: stock.id, market: market).index_by(&:report_date)
        balances = BalanceSheet.where(stock_id: stock.id, market: market).index_by(&:report_date)
        financial = financial_stock?(stock, market: market)
        reit = market == "US" && stock.industry.to_s.match?(/REIT/i)
        credit_service = market == "US" && stock.industry.to_s.match?(/信用服务|Credit\sServices/)

        updated = 0
        indicators.each do |indicator|
          result = compute_period(indicator, incomes, balances, financial, market, reit, credit_service)
          next if indicator.unlevered_roe == result[:value] && indicator.unlevered_roe_flag == result[:flag]

          indicator.update!(unlevered_roe: result[:value], unlevered_roe_flag: result[:flag])
          updated += 1
          alarm(stock, indicator, result) if [ FLAG_NORMAL, FLAG_INTEREST_MISSING, FLAG_EXTREME ].include?(result[:flag])
        end
        Rails.logger.info "[UnleveredRoeService] #{stock.symbol} #{market} 重算 #{indicators.size} 期，更新 #{updated} 条"
        { updated: updated }
      rescue => e
        Rails.logger.error "[UnleveredRoeService] #{stock&.symbol} 重算失败: #{e.message}"
        { updated: 0, error: e.message }
      end

      # 金融股判定：
      # - A股：sector=银行 或 industry 含 银行/证券/保险（沿用原口径）
      # - 美股：industry 含 银行/保险/资本市场/资产管理/金融综合/壳公司（中英文兜底）；
      #   信用服务（V/MA 等支付网络）与金融数据/交易所保留
      def financial_stock?(stock, market: stock.market)
        if market == "US"
          return false if US_CRYPTO_OPERATORS.include?(stock.symbol.to_s)

          stock.industry.to_s.match?(US_FINANCIAL_INDUSTRY)
        else
          stock.sector.to_s == "银行" || stock.industry.to_s.match?(/银行|证券|保险/)
        end
      end

      # 纯函数：科目字典 → { value:, flag:, reference_roe: }
      # ttm_np 取不到或归母净资产未入库 → flag 1；净资产/分母 ≤0 → flag 2
      # interest_missing=true（仅美股有有息负债但利息费用未披露）→ 值照算，flag 4
      def compute(ttm_np:, ttm_fin_exp:, ttm_tax:, ttm_pretax:,
                  parent_equity:, interest_debt:, financial_stock: false,
                  interest_missing: false, debt_incomplete: false)
        return { value: nil, flag: FLAG_FINANCIAL, reference_roe: nil } if financial_stock
        return { value: nil, flag: FLAG_NOT_DISCLOSED, reference_roe: nil } if ttm_np.nil? || parent_equity.nil?
        return { value: nil, flag: FLAG_NEGATIVE_EQUITY, reference_roe: nil } if parent_equity <= 0
        # REIT 债务数据不完整时分母失真，值不可信，直接隐藏
        return { value: nil, flag: FLAG_DEBT_INCOMPLETE, reference_roe: nil } if debt_incomplete

        equity = BigDecimal(parent_equity.to_s)
        denominator = equity + BigDecimal((interest_debt || 0).to_s)
        return { value: nil, flag: FLAG_NEGATIVE_EQUITY, reference_roe: nil } if denominator <= 0

        np = BigDecimal(ttm_np.to_s)
        numerator = np + after_tax_interest(ttm_fin_exp, ttm_tax, ttm_pretax)
        {
          value: (numerator / denominator * 100).round(2),
          flag: interest_missing ? FLAG_INTEREST_MISSING : FLAG_NORMAL,
          reference_roe: (np / equity * 100).round(2)
        }
      end

      private

      # 单期次：TTM 装配 + 科目取数 → 纯函数
      def compute_period(indicator, incomes, balances, financial, market, reit, credit_service)
        balance = balances[indicator.report_date]
        ttm = ttm_items(indicator, incomes, market)
        interest_debt = debt_total(balance)
        expense_missing = ttm.delete(:interest_expense_missing)
        interest_missing = interest_missing?(market, expense_missing, interest_debt)
        # 用原始净利息判断是否“真低负债”：明确利息为 0 才不标记
        debt_incomplete = reit_debt_incomplete?(reit, balance, ttm[:ttm_fin_exp]) ||
                          generic_debt_incomplete?(market, balance, interest_debt, expense_missing, ttm[:ttm_fin_exp]) ||
                          implied_rate_gap?(market, balance, interest_debt, ttm[:ttm_fin_exp]) ||
                          credit_service_debt_gap?(market, credit_service, balance, interest_debt, expense_missing)
        # 利息支出未披露且有有息负债：按约定 0 加回，不因利息收入存在而扣减
        # （否则会变成“只扣利息收入、不加回利息支出”，与口径约定相反）
        ttm[:ttm_fin_exp] = BigDecimal(0) if interest_missing

        result = compute(
          **ttm,
          parent_equity: balance&.parent_equity,
          interest_debt: interest_debt,
          financial_stock: financial,
          interest_missing: interest_missing,
          debt_incomplete: debt_incomplete
        )
        # 美股分母过小导致 -931104.99% 这类无意义数值：保留报警，但标记为极端值
        if market == "US" && result[:value] && result[:value].abs > ALARM_ABS_LIMIT
          result = result.merge(flag: FLAG_EXTREME)
        end
        result
      end

      # TTM 拼接（累计口径）：
      # 年报期直接取本期累计；非年报期 = 本期累计 + 上年年报 − 上年同期累计
      # 归母净利缺任一段 → nil（flag 1）；费用/税项缺任一段 → nil，
      # 加回项按 0 处理（茅台式全空科目自然退化为期末口径 ROE）
      def ttm_items(indicator, incomes, market)
        cur = incomes[indicator.report_date]
        return blank_ttm if cur.nil?

        return ttm_values(cur, market) if indicator.period_type == "annual"

        prior_annual = prior_annual_record(indicator, incomes, market)
        prior_same = prior_same_period_record(indicator, incomes, market)
        return blank_ttm if prior_same.nil? || prior_annual.nil?
        return blank_ttm unless prior_same.period_type == indicator.period_type
        # 上年同期必须落在上年年报之前，否则不是同一财年的累计期次
        return blank_ttm unless prior_same.report_date < prior_annual.report_date

        records = [ cur, prior_annual, prior_same ]
        np = records.map(&:net_income_to_shareholders)
        return blank_ttm if np.any?(&:nil?)

        {
          ttm_np: np[0] + np[1] - np[2],
          ttm_fin_exp: stitch_values(records.map { |r| interest_value(r, market) }),
          interest_expense_missing: market == "US" && records.any? { |r| r.interest_expense.nil? },
          ttm_tax: stitch(records, :income_tax),
          ttm_pretax: stitch(records, :income_before_tax)
        }
      end

      # 年报期：本期即 TTM，利息口径按市场归一化
      def ttm_values(record, market)
        {
          ttm_np: record.net_income_to_shareholders,
          ttm_fin_exp: interest_value(record, market),
          interest_expense_missing: market == "US" && record.interest_expense.nil?,
          ttm_tax: record.income_tax,
          ttm_pretax: record.income_before_tax
        }
      end

      # 利息口径：
      # A股 interest_expense 存的是 FINANCE_EXPENSE（已净额），直接使用；
      # 美股「利息支出」为负数毛额，净利息 = |利息支出| − |利息收入|；
      # 两者都缺失返回 nil，由 interest_missing? 决定是否 flag 4。
      def interest_value(record, market)
        return record.interest_expense unless market == "US"

        expense = record.interest_expense
        income = record.try(:interest_income)
        return nil if expense.nil? && income.nil?

        expense_value = expense.nil? ? BigDecimal(0) : BigDecimal(expense.to_s).abs
        income_value = income.nil? ? BigDecimal(0) : BigDecimal(income.to_s).abs
        expense_value - income_value
      end

      # 上年年报：
      # A股财年固定 12-31，直接取上年 12-31 年报；
      # 美股财年不固定（AAPL 9月 / MSFT 6月 / WMT 1月），取本期之前最近一期年报
      def prior_annual_record(indicator, incomes, market)
        if market == "US"
          incomes.values.select { |r| r.period_type == "annual" && r.report_date < indicator.report_date }
                 .max_by(&:report_date)
        else
          incomes[Date.new(indicator.report_date.year - 1, 12, 31)]
        end
      end

      # 上年同期累计：
      # A股用精确 -1 年；美股 52/53 周财年每年日期会漂移 1-6 天，用 ±20 天容差匹配同期次
      def prior_same_period_record(indicator, incomes, market)
        target = indicator.report_date - 1.year
        return incomes[target] unless market == "US"

        incomes.values.select do |r|
          r.period_type == indicator.period_type && (r.report_date - target).abs <= 20
        end.min_by { |r| (r.report_date - target).abs }
      end

      # 三项拼接（累计 + 上年年报 − 上年同期）：任一段缺失即返回 nil，
      # 不得按 0 静默参与运算（否则部分缺项会低估税后利息加回项）
      def stitch(records, field)
        stitch_values(records.map { |r| r.send(field) })
      end

      def stitch_values(values)
        return nil if values.any?(&:nil?)
        values[0] + values[1] - values[2]
      end

      # 仅美股：有有息负债但「利息支出」科目缺失 → flag 4；
      # 只看利息支出是否披露，不看净利息是否为 nil——否则“只有利息收入、没有利息支出”
      # 的公司会被误判为已披露，分子被扣减利息收入却没有加回利息支出
      def interest_missing?(market, expense_missing, interest_debt)
        market == "US" && expense_missing && interest_debt.to_f.positive?
      end

      # REIT 有息负债数据完整性：
      # 东财对部分 REIT 不拆分债务（埋在“其他负债/非流动负债其他项目”），
      # debt/TL < 20% 且利息费用非零（或缺失）时，分母失真，隐藏该值。
      # 明确利息费用为 0 的 REIT 可能是真低负债，不标记；
      # AMT/PLD/SPG 等拆分完整的 REIT debt/TL 约 85%，不会被误杀。
      def reit_debt_incomplete?(reit, balance, fin_exp)
        return false unless reit
        return false if balance.nil?

        total_liabilities = balance.total_liabilities.to_f
        return false unless total_liabilities.positive?
        return false if !fin_exp.nil? && fin_exp.zero?

        debt_total(balance).to_f / total_liabilities < US_REIT_MIN_DEBT_RATIO
      end

      # 非 REIT 通用债务缺口：有息负债为 0、总负债 > 2×归母权益且 > 5B，
      # 利息支出缺失（或债务为 0 但有非零利息）→ 数据源漏掉债务科目，隐藏。
      # 只有明确“利息=0”才视为真无债务；否则信用服务放贷机构（COF/AXP 等）
      # 会因只有利息收入而被误判为已披露。
      def generic_debt_incomplete?(market, balance, interest_debt, expense_missing, fin_exp)
        return false unless market == "US"
        return false if balance.nil?
        return false if interest_debt.to_f.positive?

        total_liabilities = balance.total_liabilities.to_f
        return false unless total_liabilities > US_DEBT_GAP_MIN_LIABILITIES

        equity = balance.parent_equity.to_f
        return false unless equity.positive?
        return false unless total_liabilities > equity * US_DEBT_GAP_LIABILITY_MULTIPLE

        return false if !expense_missing && fin_exp.present? && fin_exp.zero?

        true
      end

      # 非 REIT 部分债务缺口：利息费用/有息负债 > 20% 且总负债 > 1B，
      # 说明债务只抓到一部分（如 RUN 3.0x、OPEN 0.7x、SIM 20.4x）。
      def implied_rate_gap?(market, balance, interest_debt, fin_exp)
        return false unless market == "US"
        return false if balance.nil?

        debt = interest_debt.to_f
        return false unless debt.positive?

        # 只对“净利息支出”生效；净利息收入（fin_exp<0）不是债务缺口信号，
        # 否则 PLTR/CRWD/SHOP 等有利息收入、低债务的公司会被误判为 flag5。
        expense = fin_exp.to_f
        return false unless expense.positive?
        return false unless balance.total_liabilities.to_f > US_DEBT_GAP_MIN_LIABILITIES_FOR_RATE

        expense > debt * US_DEBT_GAP_MAX_IMPLIED_RATE
      end

      # 信用服务放贷机构：债务为 0、利息支出缺失且总负债 > 5B，
      # 即使 TL/权益 < 2×（如 AFRM 1.88×）也判定债务数据不完整。
      # V/MA/PYPL 有债务科目，不受影响。
      def credit_service_debt_gap?(market, credit_service, balance, interest_debt, expense_missing)
        return false unless market == "US" && credit_service
        return false if balance.nil?
        return false if interest_debt.to_f.positive?
        return false unless expense_missing

        balance.total_liabilities.to_f > US_DEBT_GAP_MIN_LIABILITIES
      end

      def blank_ttm
        { ttm_np: nil, ttm_fin_exp: nil, interest_expense_missing: false,
          ttm_tax: nil, ttm_pretax: nil }
      end

      # 有息负债合计：四科目求和，全 NULL 视为 0（无借款公司如茅台）
      def debt_total(balance)
        return nil if balance.nil?
        [ balance.short_term_debt, balance.long_term_debt,
          balance.bond_payable, balance.noncurrent_liab_1year ].compact.sum
      end

      # 税后净财务费用加回项：
      # 实际税率仅在 0 ≤ 税 < 税前利润 时采信，否则取 0（亏损企业无抵税，全额加回）；
      # 财务费用为净额（含利息收入抵减），负数加回即反向修正，方向自洽
      def after_tax_interest(fin_exp, tax, pretax)
        return BigDecimal(0) if fin_exp.nil?

        rate = if pretax && pretax > 0 && tax && tax >= 0 && tax <= pretax
                 BigDecimal(tax.to_s) / BigDecimal(pretax.to_s)
               else
                 BigDecimal(0)
               end
        BigDecimal(fin_exp.to_s) * (1 - rate)
      end

      # 复核报警：只落台账不中断主流程（口径B下 value>参考ROE 有合法情形——
      # 借款利率高于资本回报时去杠杆反而提升回报，故阈值放宽到 +10pp）
      def alarm(stock, indicator, result)
        value = result[:value]
        return if value.nil?

        if value.abs > ALARM_ABS_LIMIT
          Rails.logger.warn "[UnleveredRoeService] #{stock.symbol} #{indicator.report_date} 无杠杆ROE绝对值异常: #{value}"
          DataQualityIssue.record!(stock, "financial", "unlevered_roe_outlier", severity: "warning",
                                   detail: { report_date: indicator.report_date.to_s, value: value.to_s })
        end

        # 仅在盈利企业上比对才有 bug 信号意义：亏损公司分母扩大会合法地
        # 使无杠杆ROE高于参考ROE（损失被稀释），不报警
        ref = result[:reference_roe]
        return unless ref && ref > 0 && value > ref + ALARM_ABOVE_ROE_PP

        Rails.logger.warn "[UnleveredRoeService] #{stock.symbol} #{indicator.report_date} 无杠杆ROE(#{value}) 显著高于参考ROE(#{ref})"
        DataQualityIssue.record!(stock, "financial", "unlevered_roe_above_roe", severity: "warning",
                                 detail: { report_date: indicator.report_date.to_s, value: value.to_s, reference_roe: ref.to_s })
      rescue => e
        Rails.logger.error "[UnleveredRoeService] #{stock.symbol} 报警落账失败: #{e.message}"
      end
    end
  end
end
