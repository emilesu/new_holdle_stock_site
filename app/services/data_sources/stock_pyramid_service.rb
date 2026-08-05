module DataSources
  # 金字塔分数计算服务
  # 依据金字塔9项打分规则计算股票总分，仅存储累加后的总分
  class StockPyramidService
    class << self
      # 主入口方法
      # @param stock [Stock] 股票对象
      # @return [Hash] 计算结果 { success: Boolean, old_score: Integer, new_score: Integer, error: String, updated: Boolean }
      def call(stock)
        return { success: false, old_score: 0, new_score: 0, error: '股票不存在' } unless stock
        
        old_score = stock.pyramid_total_score.to_i
        
        begin
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
      end

      private

      # 计算金字塔总分（9项指标累加）
      # @param stock [Stock] 股票对象
      # @param all_data [Array] 近5年财务数据
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
          Rails.logger.info "[PyramidService] #{symbol} year=#{d[:year]}, roe=#{d[:roe]}, roa=#{d[:roa]}, gross_margin=#{d[:gross_margin]}, net_income=#{d[:net_income]}, asset_turnover=#{d[:asset_turnover_ratio]}, operating_cf=#{d[:operating_cash_flow]}, cash_ratio=#{d[:cash_to_assets_ratio]}"
        end

        roe_score = calculate_roe_score(all_data)
        score += roe_score
        Rails.logger.info "[PyramidService] #{symbol} ROE得分: #{roe_score}, 累计: #{score}"

        roa_score = calculate_roa_score(all_data, roe_score)
        score += roa_score
        Rails.logger.info "[PyramidService] #{symbol} ROA得分: #{roa_score}, 累计: #{score}"

        ni_score = calculate_net_income_score(all_data)
        score += ni_score
        Rails.logger.info "[PyramidService] #{symbol} 净利润规模得分: #{ni_score}, 累计: #{score}"

        turnover_score = calculate_asset_turnover_score(all_data)
        score += turnover_score
        Rails.logger.info "[PyramidService] #{symbol} 资产周转率得分: #{turnover_score}, 累计: #{score}"

        gm_score = calculate_gross_margin_score(stock, all_data)
        score += gm_score
        Rails.logger.info "[PyramidService] #{symbol} 毛利率得分: #{gm_score}, 累计: #{score}"

        growth_score = calculate_net_profit_growth_score(stock, all_data)
        score += growth_score
        Rails.logger.info "[PyramidService] #{symbol} 净利润增长率得分: #{growth_score}, 累计: #{score}"

        cf_score = calculate_cash_flow_growth_score(all_data)
        score += cf_score
        Rails.logger.info "[PyramidService] #{symbol} 经营现金流增长得分: #{cf_score}, 累计: #{score}"

        cash_ratio_score = calculate_cash_ratio_score(all_data)
        score += cash_ratio_score
        Rails.logger.info "[PyramidService] #{symbol} 现金占总资产比率得分: #{cash_ratio_score}, 累计: #{score}"

        final_score = score.clamp(0, 1000)
        Rails.logger.info "[PyramidService] #{symbol} 总分(限制后): #{final_score}"
        final_score
      end

      # 计算ROE分数（权重最高，0-550分）
      # 近5年ROE平均值，任一为负则得0分
      # 线性插值：10%~35%按档位平滑过渡，消除档位边界跳跃（如24.9%与25.0%不再差50分）
      # 特殊规则：均值>=25%但最大值超过最小值4倍时，一律计450分（不少于3年数据即执行）
      def calculate_roe_score(all_data)
        roe_values = all_data.map { |d| d[:roe] }.compact.map(&:to_f)
        return 0 if roe_values.size < 3

        any_negative = roe_values.any? { |v| v <= 0 }
        return 0 if any_negative

        avg_roe = roe_values.sum / roe_values.size

        # 档位基准：[ROE下限, 对应分数]，区间内线性插值
        steps = [[10, 300], [15, 350], [20, 400], [25, 450], [30, 500], [35, 550]]
        if avg_roe >= 35
          score = 550  # 卓越：ROE >= 35%
        elsif avg_roe < 10
          score = 0    # 低于10%不得分
        else
          (lo, lo_score), (hi, hi_score) = steps.each_cons(2).find do |(lo, _), (hi, _)|
            avg_roe >= lo && avg_roe < hi
          end
          score = lo_score + (avg_roe - lo) / (hi - lo) * (hi_score - lo_score)
        end

        recent_roe = roe_values.last(5)
        if avg_roe >= 25 && recent_roe.size >= 3
          max_roe = recent_roe.max
          min_roe = recent_roe.min
          if min_roe > 0 && max_roe / min_roe > 4
            score = 450
          end
        end

        score.round
      end

      # 计算ROA分数（0-100分）
      # ROE已获高分(>=450，均值约25%+)时ROA减半，避免同一经营质量重复计分；
      # ROE一般但ROA高的低杠杆公司ROA全额给分，作为独立奖励
      def calculate_roa_score(all_data, roe_score)
        roa_values = all_data.map { |d| d[:roa] }.compact.map(&:to_f)
        return 0 if roa_values.size < 3

        avg_roa = roa_values.sum / roa_values.size

        score = case
        when avg_roa >= 15 then 100  # 优秀
        when avg_roa >= 11 then 80   # 良好
        when avg_roa >= 7 then 50    # 及格
        else 0
        end

        score = (score * 0.5).round if roe_score >= 450
        score
      end

      # 计算净利润规模分数（0-200分）
      # 五档阶梯：千亿级200 / 五百亿级150 / 百亿级100 / 盈利50 / 亏损0
      def calculate_net_income_score(all_data)
        ni_values = all_data.map { |d| d[:net_income] }.compact.map(&:to_f)
        return 0 if ni_values.size < 5

        avg_ni = ni_values.sum / ni_values.size

        case
        when avg_ni >= 1000_0000_0000 then 200  # 千亿级
        when avg_ni >= 500_0000_0000 then 150   # 五百亿级
        when avg_ni >= 100_0000_0000 then 100   # 百亿级
        when avg_ni > 0 then 50                 # 盈利
        else 0
        end
      end

      # 计算资产周转率分数（0-50分）
      def calculate_asset_turnover_score(all_data)
        turnover_values = all_data.map { |d| d[:asset_turnover_ratio] }.compact.map(&:to_f)
        return 0 if turnover_values.size < 5

        avg_turnover = turnover_values.sum / turnover_values.size

        avg_turnover > 80 ? 50 : 0  # 周转率超过80%得50分
      end

      # 计算毛利率分数（0-50分）
      def calculate_gross_margin_score(stock, all_data)
        gm_values = all_data.map { |d| d[:gross_margin] }.compact.map(&:to_f)
        return 0 if gm_values.size < 5

        avg_gm = gm_values.sum / gm_values.size

        avg_gm > 30 ? 50 : 0  # 毛利率超过30%得50分
      end

      # 计算净利润增长分数（-90至90分）
      # 规则：负值年份不参与计分（避免"亏损收窄=成长"失真）；
      #       增长按幅度分档：增幅>=20%按1.5倍权重、5%~20%全额、<5%半权（微增不当作真成长）；
      #       降幅<=5%视为正常波动不扣分、5%~15%半扣、>15%全额扣
      def calculate_net_profit_growth_score(stock, all_data)
        ni_values = all_data.map { |d| d[:net_income] }.compact.map(&:to_f)
        return 0 if ni_values.size < 5

        score = 0
        years = [0, 1, 2, 3]       # 最近4年对比（i=0最早两年 → i=3最近两年）
        weights = [15, 20, 25, 30] # 权重递增：越接近当前年份权重越高

        years.each_with_index do |i, idx|
          next if i + 1 >= ni_values.size
          old_value = ni_values[i]
          new_value = ni_values[i + 1]
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

      # 计算经营现金流增长分数（-90至90分）
      # 使用经营活动现金流量(operating_cash_flow)数据，计分规则与净利润增长分数一致
      def calculate_cash_flow_growth_score(all_data)
        cf_values = all_data.map { |d| d[:operating_cash_flow] }.compact.map(&:to_f)
        return 0 if cf_values.size < 5

        score = 0
        years = [0, 1, 2, 3]       # 最近4年对比（i=0最早两年 → i=3最近两年）
        weights = [15, 20, 25, 30] # 权重递增：越接近当前年份权重越高

        years.each_with_index do |i, idx|
          next if i + 1 >= cf_values.size
          old_value = cf_values[i]
          new_value = cf_values[i + 1]
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
        cr_values = all_data.map { |d| d[:cash_to_assets_ratio] }.compact.map(&:to_f)
        return 0 if cr_values.size < 3

        roe_values = all_data.map { |d| d[:roe] }.compact.map(&:to_f)
        return 0 if roe_values.size < 3 || roe_values.any? { |v| v <= 0 }

        avg_cr = cr_values.sum / cr_values.size

        case
        when avg_cr >= 20 then 50  # 现金充裕，抗风险能力强
        when avg_cr >= 10 then 25  # 现金充足
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

      # 分数不变时仅更新时间戳，提供视觉反馈
      def touch_timestamp(stock)
        stock.update!(last_pyramid_calc_at: Time.current)
      end
    end
  end
end