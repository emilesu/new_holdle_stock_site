module DataSources
  # 金字塔分数计算服务（方案B规则，2026-11-27 定稿）
  # 依据10项打分规则计算股票总分，仅存储累加后的总分（0-1000）
  #
  # 计分结构（理论满分1290，clamp到1000，塔尖并列属设计接受范围）：
  #   1. ROE水平分 0-400：近5年ROE按[1,1,2,3,3]近年加权均值，10%~35%线性插值后×400/550；
  #      衰退折扣（近3年均值<全期均值×0.7 → ×0.8）；杠杆质量调节（无杠杆ROE/ROE比值 → ×1.0/0.9/0.8/0.7）
  #   2. ROE稳定分 0-150：每年ROE均≥15%→150，均≥10%→100，其余→40（任一年≤0则ROE两项全归零）
  #   3. ROA 0-100：≥15%→100 / ≥11%→80 / ≥7%→50（不再因ROE高分减半）
  #   4. 净利润规模 0-200：5年均值 千亿→200 / 五百亿→150 / 百亿→100 / 盈利→50
  #   5. 资产周转率 0-50：5年均值>0.8次得50
  #   6. 毛利率 0-100：水平分（≥50%→60 / ≥40%→45 / ≥30%→30 / ≥20%→15）+ 稳定分（5年极差<5pp→40 / <10pp→20）
  #   7. 净利润增长 -90~90：逐年对比，权重[15,20,25,30]递增，增幅分档加权
  #   8. 经营现金流增长 -90~90：规则同7
  #   9. 现金占总资产比率 0-50：≥20%→50 / ≥10%→25（ROE有负值或数据不足时归零）
  #  10. 净现比 0-60：5年逐年经营现金流/净利润（仅净利>0年份）均值 ≥1.0→60 / ≥0.8→30
  class StockPyramidService
    # ROE 插值档位：[ROE下限, 对应分数]（0-550口径，水平分按400/550等比压缩）
    ROE_STEPS = [[10, 300], [15, 350], [20, 400], [25, 450], [30, 500], [35, 550]].freeze
    # ROE 近年加权权重（最早 → 最近）
    RECENCY_WEIGHTS = [1, 1, 2, 3, 3].freeze
    # 杠杆质量调节档位：[无杠杆ROE均值/ROE均值 下限, ROE水平分系数]
    LEVERAGE_TIERS = [[0.85, 1.0], [0.70, 0.9], [0.55, 0.8]].freeze
    LEVERAGE_FLOOR_FACTOR = 0.7
    # 水平分压缩比：旧550口径 → 新400口径
    ROE_LEVEL_SCALE = 400.0 / 550

    class << self
      # 主入口方法
      # @param stock [Stock] 股票对象
      # @return [Hash] 计算结果 { success: Boolean, old_score: Integer, new_score: Integer, error: String, updated: Boolean }
      def call(stock)
        return { success: false, old_score: 0, new_score: 0, error: '股票不存在' } unless stock

        old_score = stock.pyramid_total_score.to_i

        result = begin
          new_score = calculate_total_score(stock)

          if new_score == old_score
            touch_timestamp(stock)
            { success: true, old_score: old_score, new_score: new_score, error: nil, updated: true }
          else
            update_stock(stock, new_score)
            { success: true, old_score: old_score, new_score: new_score, error: nil, updated: true }
          end
        rescue => e
          Rails.logger.error "StockPyramidService error for #{stock.symbol}: #{e.message}"
          update_stock(stock, 0)
          { success: false, old_score: old_score, new_score: 0, error: e.message, updated: true }
        end

        # 每次重算后都清理行业对比缓存：即使分数未变化，也可能存在"库中已是最新但缓存仍为旧快照"的陈旧数据
        invalidate_industry_comparison_cache(stock)
        result
      end

      private

      # 计算金字塔总分（10项指标累加）
      # @param stock [Stock] 股票对象
      # @return [Integer] 总分（0-1000分）
      def calculate_total_score(stock)
        score = 0
        symbol = stock.symbol

        financial_years = stock.financial_years.select { |y| y.to_i >= Date.current.year - 5 }.sort.last(5)
        Rails.logger.info "[PyramidService] #{symbol} financial_years(近5年): #{financial_years.inspect}"
        return 0.tap { Rails.logger.warn "[PyramidService] #{symbol} 无财务年份数据，总分=0" } if financial_years.empty?

        all_data = financial_years.map { |year| stock.get_financial_data_by_year(year) }.compact
        Rails.logger.info "[PyramidService] #{symbol} all_data 数量: #{all_data.size}"
        return 0.tap { Rails.logger.warn "[PyramidService] #{symbol} 财务数据为空，总分=0" } if all_data.empty?

        # 记录每个年份的关键指标
        all_data.each_with_index do |d, i|
          Rails.logger.info "[PyramidService] #{symbol} year=#{d[:year]}, roe=#{d[:roe]}, roa=#{d[:roa]}, gross_margin=#{d[:gross_margin]}, net_income=#{d[:net_income]}, asset_turnover_ratio=#{d[:asset_turnover_ratio]}, operating_cf=#{d[:operating_cash_flow]}, cash_ratio=#{d[:cash_to_assets_ratio]}, unlevered_roe=#{d[:unlevered_roe]}"
        end

        roe = calculate_roe_score(all_data)
        score += roe[:level] + roe[:stability]
        Rails.logger.info "[PyramidService] #{symbol} ROE得分: 水平#{roe[:level]} + 稳定#{roe[:stability]}, 累计: #{score}"

        roa_score = calculate_roa_score(all_data)
        score += roa_score
        Rails.logger.info "[PyramidService] #{symbol} ROA得分: #{roa_score}, 累计: #{score}"

        ni_score = calculate_net_income_score(all_data)
        score += ni_score
        Rails.logger.info "[PyramidService] #{symbol} 净利润规模得分: #{ni_score}, 累计: #{score}"

        turnover_score = calculate_asset_turnover_score(all_data)
        score += turnover_score
        Rails.logger.info "[PyramidService] #{symbol} 资产周转率得分: #{turnover_score}, 累计: #{score}"

        gm_score = calculate_gross_margin_score(all_data)
        score += gm_score
        Rails.logger.info "[PyramidService] #{symbol} 毛利率得分: #{gm_score}, 累计: #{score}"

        growth_score = calculate_net_profit_growth_score(all_data)
        score += growth_score
        Rails.logger.info "[PyramidService] #{symbol} 净利润增长率得分: #{growth_score}, 累计: #{score}"

        cf_score = calculate_cash_flow_growth_score(all_data)
        score += cf_score
        Rails.logger.info "[PyramidService] #{symbol} 经营现金流增长得分: #{cf_score}, 累计: #{score}"

        cash_ratio_score = calculate_cash_ratio_score(all_data)
        score += cash_ratio_score
        Rails.logger.info "[PyramidService] #{symbol} 现金占总资产比率得分: #{cash_ratio_score}, 累计: #{score}"

        ncr_score = calculate_net_cash_ratio_score(all_data)
        score += ncr_score
        Rails.logger.info "[PyramidService] #{symbol} 净现比得分: #{ncr_score}, 累计: #{score}"

        final_score = score.clamp(0, 1000)
        Rails.logger.info "[PyramidService] #{symbol} 总分(限制后): #{final_score}"
        final_score
      end

      # ROE 得分（方案B拆分）：水平分 0-400 + 稳定分 0-150
      # 数据门槛：≥3年且任一年≤0 → 两项全归零
      def calculate_roe_score(all_data)
        roe_values = all_data.filter_map { |d| d[:roe]&.to_f }
        return { level: 0, stability: 0 } if roe_values.size < 3 || roe_values.any? { |v| v <= 0 }

        avg_roe = weighted_roe_avg(roe_values)
        level = interpolate_roe_score(avg_roe) * ROE_LEVEL_SCALE
        level *= 0.8 if declining?(roe_values)
        level *= leverage_factor(all_data)

        stability = if roe_values.all? { |v| v >= 15 } then 150
                    elsif roe_values.all? { |v| v >= 10 } then 100
                    else 40
                    end

        { level: level.round, stability: stability }
      end

      # 近5年ROE近年加权均值（权重[1,1,2,3,3]，数据不足5年时取尾部权重）
      def weighted_roe_avg(roe_values)
        weights = RECENCY_WEIGHTS.last(roe_values.size)
        roe_values.zip(weights).sum { |v, w| v * w } / weights.sum.to_f
      end

      # 线性插值（0-550口径）：区间内平滑过渡，消除档位边界跳跃
      def interpolate_roe_score(avg_roe)
        return 550 if avg_roe >= 35
        return 0 if avg_roe < 10

        (lo, lo_score), (hi, hi_score) = ROE_STEPS.each_cons(2).find do |(l, _), (h, _)|
          avg_roe >= l && avg_roe < h
        end
        lo_score + (avg_roe - lo) / (hi - lo) * (hi_score - lo_score)
      end

      # 衰退折扣：近3年简单均值 < 全期简单均值×0.7 → 盈利能力系统性下滑
      # 数据仅3年时近3年即全期，不会触发
      def declining?(roe_values)
        return false if roe_values.size < 4

        recent_avg = roe_values.last(3).sum / 3.0
        full_avg = roe_values.sum / roe_values.size.to_f
        recent_avg < full_avg * 0.7
      end

      # 杠杆质量调节：无杠杆ROE均值/ROE均值 比值越接近1，回报越不依赖杠杆
      # 仅统计无杠杆ROE非空的年份（flag 1/2/3/5/6 在组装层已置 nil）；
      # 有效年份<3（港股未接入/金融股/缺失）不惩罚，返回1.0
      def leverage_factor(all_data)
        pairs = all_data.filter_map do |d|
          u = d[:unlevered_roe]
          r = d[:roe]
          [u.to_f, r.to_f] if u.present? && r.present?
        end
        return 1.0 if pairs.size < 3

        avg_unlevered = pairs.sum { |u, _| u } / pairs.size.to_f
        avg_roe = pairs.sum { |_, r| r } / pairs.size.to_f
        return 1.0 if avg_roe <= 0

        ratio = avg_unlevered / avg_roe
        LEVERAGE_TIERS.each { |threshold, factor| return factor if ratio >= threshold }
        LEVERAGE_FLOOR_FACTOR
      end

      # 计算ROA分数（0-100分）
      # 方案B起取消「ROE高分时ROA减半」：杠杆维度已由无杠杆ROE比值调节承担，ROA作为独立全额奖励项
      def calculate_roa_score(all_data)
        roa_values = all_data.filter_map { |d| d[:roa]&.to_f }
        return 0 if roa_values.size < 3

        avg_roa = roa_values.sum / roa_values.size.to_f

        case
        when avg_roa >= 15 then 100  # 优秀
        when avg_roa >= 11 then 80   # 良好
        when avg_roa >= 7 then 50    # 及格
        else 0
        end
      end

      # 计算净利润规模分数（0-200分）
      # 五档阶梯：千亿级200 / 五百亿级150 / 百亿级100 / 盈利50 / 亏损0
      def calculate_net_income_score(all_data)
        ni_values = all_data.filter_map { |d| d[:net_income]&.to_f }
        return 0 if ni_values.size < 5

        avg_ni = ni_values.sum / ni_values.size.to_f

        case
        when avg_ni >= 1000_0000_0000 then 200  # 千亿级
        when avg_ni >= 500_0000_0000 then 150   # 五百亿级
        when avg_ni >= 100_0000_0000 then 100   # 百亿级
        when avg_ni > 0 then 50                 # 盈利
        else 0
        end
      end

      # 计算资产周转率分数（0-50分）
      # 数据口径：asset_turnover_ratio = 营业总收入/总资产，存储为「次」的小数形式（如 0.54 = 54%），
      # 与雷达图 normalize_asset_turnover 的 ×100 换算口径一致；阈值为 0.8 次（即 80%）
      def calculate_asset_turnover_score(all_data)
        turnover_values = all_data.filter_map { |d| d[:asset_turnover_ratio]&.to_f }
        return 0 if turnover_values.size < 5

        avg_turnover = turnover_values.sum / turnover_values.size.to_f

        avg_turnover > 0.8 ? 50 : 0  # 周转率超过80%（0.8次）得50分
      end

      # 计算毛利率分数（0-100分，方案B扩容）
      # 水平分（0-60）：均值分档，突出定价权；稳定分（0-40）：5年极差，毛利率不滑坡=护城河稳固
      def calculate_gross_margin_score(all_data)
        gm_values = all_data.filter_map { |d| d[:gross_margin]&.to_f }
        return 0 if gm_values.size < 5

        avg_gm = gm_values.sum / gm_values.size.to_f
        level = if avg_gm >= 50 then 60
                elsif avg_gm >= 40 then 45
                elsif avg_gm >= 30 then 30
                elsif avg_gm >= 20 then 15
                else 0
                end

        spread = gm_values.max - gm_values.min
        stability = if spread < 5 then 40
                    elsif spread < 10 then 20
                    else 0
                    end

        level + stability
      end

      # 计算净利润增长分数（-90至90分）
      # 规则：负值年份不参与计分（避免"亏损收窄=成长"失真）；
      #       增长按幅度分档：增幅>=20%按1.5倍权重、5%~20%全额、<5%半权（微增不当作真成长）；
      #       降幅<=5%视为正常波动不扣分、5%~15%半扣、>15%全额扣
      def calculate_net_profit_growth_score(all_data)
        growth_score(all_data.filter_map { |d| d[:net_income]&.to_f })
      end

      # 计算经营现金流增长分数（-90至90分）
      # 使用经营活动现金流量(operating_cash_flow)数据，计分规则与净利润增长分数一致
      def calculate_cash_flow_growth_score(all_data)
        growth_score(all_data.filter_map { |d| d[:operating_cash_flow]&.to_f })
      end

      # 增长计分核心（净利润/经营现金流共用）：最近4组逐年对比，越接近当前年份权重越高
      def growth_score(values)
        return 0 if values.size < 5

        score = 0
        weights = [15, 20, 25, 30]

        [0, 1, 2, 3].each_with_index do |i, idx|
          next if i + 1 >= values.size
          old_value = values[i]
          new_value = values[i + 1]
          next if old_value == 0

          if old_value < 0 || new_value < 0
            # 盈利转亏损（正→负）是重大负面信号，全额扣分；
            # 其余含负值段（亏损收窄/扭亏）不参与计分，避免"亏损收窄=成长"失真
            score -= weights[idx] if old_value > 0 && new_value < 0
            next
          end

          if new_value > old_value
            growth_ratio = (new_value - old_value) / old_value.abs * 100
            if growth_ratio >= 20
              score += weights[idx] * 1.5  # 高增长1.5倍权重
            elsif growth_ratio >= 5
              score += weights[idx]        # 正常增长
            else
              score += weights[idx] * 0.5  # 微增长半权
            end
          else
            drop_ratio = (old_value - new_value) / old_value.abs * 100
            if drop_ratio > 15
              score -= weights[idx]        # 大降幅全额扣分
            elsif drop_ratio > 5
              score -= weights[idx] * 0.5  # 中降幅半扣
            end
          end
        end

        score.round.clamp(-90, 90)
      end

      # 计算现金占总资产比率分数（0-50分）
      # 近5年现金占总资产比率平均值，≥20%得50分，≥10%得25分；
      # ROE存在负值或ROE数据不足3年的公司现金分归零
      #（账上有钱但经营亏损/数据缺失，不应获得抗风险奖励，与ROE分数据口径一致）
      def calculate_cash_ratio_score(all_data)
        cr_values = all_data.filter_map { |d| d[:cash_to_assets_ratio]&.to_f }
        return 0 if cr_values.size < 3

        roe_values = all_data.filter_map { |d| d[:roe]&.to_f }
        return 0 if roe_values.size < 3 || roe_values.any? { |v| v <= 0 }

        avg_cr = cr_values.sum / cr_values.size.to_f

        case
        when avg_cr >= 20 then 50  # 现金充裕，抗风险能力强
        when avg_cr >= 10 then 25  # 现金充足
        else 0
        end
      end

      # 计算净现比分数（0-60分，方案B新增）
      # 逐年经营现金流/净利润（仅统计净利润>0的年份），有效年份≥3才计分；
      # 5年均值 ≥1.0→60（利润全部转化为现金）/ ≥0.8→30 / 其余0
      def calculate_net_cash_ratio_score(all_data)
        ratios = all_data.filter_map do |d|
          ni = d[:net_income]
          ocf = d[:operating_cash_flow]
          next if ni.nil? || ocf.nil?
          ni = ni.to_f
          ocf.to_f / ni if ni > 0
        end
        return 0 if ratios.size < 3

        avg = ratios.sum / ratios.size.to_f
        if avg >= 1.0 then 60
        elsif avg >= 0.8 then 30
        else 0
        end
      end

      # 更新股票金字塔分数
      def update_stock(stock, score)
        stock.update!(
          pyramid_total_score: score,
          last_pyramid_calc_at: Time.current
        )
      end

      # 删除股票详情页右侧"行业金字塔对比"栏缓存，
      # 避免缓存快照(12小时TTL)持续显示旧分数
      def invalidate_industry_comparison_cache(stock)
        return if stock.sector.blank? || stock.market.blank?

        # 缓存键格式: industry_comparison/v2/{sector}/{market}/{date}，
        # 删除今天与昨天两天键，覆盖 12 小时 TTL 的跨天边界场景
        [Date.current, Date.current - 1.day].each do |date|
          key = [:industry_comparison, "v2", stock.sector, stock.market, date].join('/')
          Rails.cache.delete(key)
        end
      rescue => e
        Rails.logger.warn "[PyramidService] 行业对比缓存失效失败 #{stock.symbol}: #{e.message}"
      end

      # 分数不变时仅更新时间戳，提供视觉反馈
      def touch_timestamp(stock)
        stock.update!(last_pyramid_calc_at: Time.current)
      end
    end
  end
end
