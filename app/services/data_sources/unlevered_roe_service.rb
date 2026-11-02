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
    FLAG_NORMAL = 0          # 正常
    FLAG_NOT_DISCLOSED = 1   # 未披露/数据不全（含未重爬新科目的历史期次）
    FLAG_NEGATIVE_EQUITY = 2 # 净资产≤0，指标无意义
    FLAG_FINANCIAL = 3       # 金融股（银行/券商/保险）不适用，口径冻结直接剔除

    # 复核报警阈值：显著高于期末口径 TTM ROE 参考值，或绝对值超出常识区间
    ALARM_ABOVE_ROE_PP = 10.0
    ALARM_ABS_LIMIT = 100.0

    # flag≠0 时前端悬浮原因（值显示为 — 的具体语义）
    FLAG_REASONS = {
      FLAG_NOT_DISCLOSED => "财报科目未披露或尚未采集",
      FLAG_NEGATIVE_EQUITY => "归母净资产≤0，指标不适用",
      FLAG_FINANCIAL => "金融股（银行/券商/保险）不适用本指标"
    }.freeze

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
        financial = financial_stock?(stock)

        updated = 0
        indicators.each do |indicator|
          result = compute_period(indicator, incomes, balances, financial)
          next if indicator.unlevered_roe == result[:value] && indicator.unlevered_roe_flag == result[:flag]

          indicator.update!(unlevered_roe: result[:value], unlevered_roe_flag: result[:flag])
          updated += 1
          alarm(stock, indicator, result) if result[:flag] == FLAG_NORMAL
        end
        Rails.logger.info "[UnleveredRoeService] #{stock.symbol} #{market} 重算 #{indicators.size} 期，更新 #{updated} 条"
        { updated: updated }
      rescue => e
        Rails.logger.error "[UnleveredRoeService] #{stock&.symbol} 重算失败: #{e.message}"
        { updated: 0, error: e.message }
      end

      # 金融股判定：A股行业口径（sector=银行 或 industry 含 银行/证券/保险）
      def financial_stock?(stock)
        stock.sector.to_s == "银行" || stock.industry.to_s.match?(/银行|证券|保险/)
      end

      # 纯函数：科目字典 → { value:, flag:, reference_roe: }
      # ttm_np 取不到或归母净资产未入库 → flag 1；净资产/分母 ≤0 → flag 2
      def compute(ttm_np:, ttm_fin_exp:, ttm_tax:, ttm_pretax:,
                  parent_equity:, interest_debt:, financial_stock: false)
        return { value: nil, flag: FLAG_FINANCIAL, reference_roe: nil } if financial_stock
        return { value: nil, flag: FLAG_NOT_DISCLOSED, reference_roe: nil } if ttm_np.nil? || parent_equity.nil?
        return { value: nil, flag: FLAG_NEGATIVE_EQUITY, reference_roe: nil } if parent_equity <= 0

        equity = BigDecimal(parent_equity.to_s)
        denominator = equity + BigDecimal((interest_debt || 0).to_s)
        return { value: nil, flag: FLAG_NEGATIVE_EQUITY, reference_roe: nil } if denominator <= 0

        np = BigDecimal(ttm_np.to_s)
        numerator = np + after_tax_interest(ttm_fin_exp, ttm_tax, ttm_pretax)
        {
          value: (numerator / denominator * 100).round(2),
          flag: FLAG_NORMAL,
          reference_roe: (np / equity * 100).round(2)
        }
      end

      private

      # 单期次：TTM 装配 + 科目取数 → 纯函数
      def compute_period(indicator, incomes, balances, financial)
        balance = balances[indicator.report_date]
        ttm = ttm_items(indicator, incomes)

        compute(
          **ttm,
          parent_equity: balance&.parent_equity,
          interest_debt: debt_total(balance),
          financial_stock: financial
        )
      end

      # TTM 拼接（A股财年12-31，累计口径）：
      # 年报期直接取本期累计；非年报期 = 最新累计 + 上年年报 − 上年同期累计
      # 归母净利缺任一段 → nil（flag 1）；费用/税项缺任一段 → nil，
      # 加回项按 0 处理（茅台式全空科目自然退化为期末口径 ROE）
      def ttm_items(indicator, incomes)
        cur = incomes[indicator.report_date]
        return blank_ttm if cur.nil?

        return {
          ttm_np: cur.net_income_to_shareholders,
          ttm_fin_exp: cur.interest_expense,
          ttm_tax: cur.income_tax,
          ttm_pretax: cur.income_before_tax
        } if indicator.period_type == "annual"

        prior_same = incomes[indicator.report_date - 1.year]
        prior_annual = incomes[Date.new(indicator.report_date.year - 1, 12, 31)]
        return blank_ttm if prior_same.nil? || prior_annual.nil?
        return blank_ttm unless prior_same.period_type == indicator.period_type

        np = [ cur.net_income_to_shareholders,
               prior_annual.net_income_to_shareholders,
               prior_same.net_income_to_shareholders ]
        return blank_ttm if np.any?(&:nil?)

        {
          ttm_np: np[0] + np[1] - np[2],
          ttm_fin_exp: stitch([ cur, prior_annual, prior_same ], :interest_expense),
          ttm_tax: stitch([ cur, prior_annual, prior_same ], :income_tax),
          ttm_pretax: stitch([ cur, prior_annual, prior_same ], :income_before_tax)
        }
      end

      # 三项拼接（累计 + 上年年报 − 上年同期）：任一段缺失即返回 nil，
      # 不得按 0 静默参与运算（否则部分缺项会低估税后利息加回项）
      def stitch(records, field)
        values = records.map { |r| r.send(field) }
        return nil if values.any?(&:nil?)
        values[0] + values[1] - values[2]
      end

      def blank_ttm
        { ttm_np: nil, ttm_fin_exp: nil, ttm_tax: nil, ttm_pretax: nil }
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
