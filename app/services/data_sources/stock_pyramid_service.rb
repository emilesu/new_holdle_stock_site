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

        roa_score = calculate_roa_score(all_data)
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
      def calculate_roe_score(all_data)
        roe_values = all_data.map { |d| d[:roe] }.compact.map(&:to_f)
        return 0 if roe_values.size < 3

        any_negative = roe_values.any? { |v| v <= 0 }
        return 0 if any_negative

        avg_roe = roe_values.sum / roe_values.size

        case
        when avg_roe >= 35 then 550  # 卓越：ROE >= 35%
        when avg_roe >= 30 then 500  # 优秀：ROE >= 30%
        when avg_roe >= 25 then 450  # 良好：ROE >= 25%
        when avg_roe >= 20 then 400  # 中等偏上：ROE >= 20%
        when avg_roe >= 15 then 350  # 中等：ROE >= 15%
        when avg_roe >= 10 then 300  # 及格：ROE >= 10%
        else 0
        end
      end

      # 计算ROA分数（0-100分）
      def calculate_roa_score(all_data)
        roa_values = all_data.map { |d| d[:roa] }.compact.map(&:to_f)
        return 0 if roa_values.size < 3

        avg_roa = roa_values.sum / roa_values.size

        case
        when avg_roa >= 15 then 100  # 优秀
        when avg_roa >= 11 then 80   # 良好
        when avg_roa >= 7 then 50    # 及格
        else 0
        end
      end

      # 计算净利润规模分数（0-150分）
      def calculate_net_income_score(all_data)
        ni_values = all_data.map { |d| d[:net_income] }.compact.map(&:to_f)
        return 0 if ni_values.size < 5

        avg_ni = ni_values.sum / ni_values.size

        case
        when avg_ni >= 100_0000_0000 then 150  # 千亿级
        when avg_ni >= 10_0000_0000 then 100   # 百亿级
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
      def calculate_net_profit_growth_score(stock, all_data)
        ni_values = all_data.map { |d| d[:net_income] }.compact.map(&:to_f)
        return 0 if ni_values.size < 5

        score = 0
        years = [0, 1, 2, 3]     # 最近4年对比
        weights = [30, 25, 20, 15] # 权重递减

        years.each_with_index do |i, idx|
          next if i + 1 >= ni_values.size
          score += weights[idx] if ni_values[i] < ni_values[i + 1]  # 增长加分（后值更大）
          score -= weights[idx] if ni_values[i] > ni_values[i + 1]  # 下降扣分（前值更大）
        end

        score.clamp(-90, 90)
      end

      # 计算经营现金流增长分数（-90至90分）
      # 使用经营活动现金流量(operating_cash_flow)数据，逻辑与净利润增长分数一致
      def calculate_cash_flow_growth_score(all_data)
        cf_values = all_data.map { |d| d[:operating_cash_flow] }.compact.map(&:to_f)
        return 0 if cf_values.size < 5

        score = 0
        years = [0, 1, 2, 3]     # 最近4年对比
        weights = [30, 25, 20, 15] # 权重递减

        years.each_with_index do |i, idx|
          next if i + 1 >= cf_values.size
          score += weights[idx] if cf_values[i] < cf_values[i + 1]  # 增长加分（后值更大）
          score -= weights[idx] if cf_values[i] > cf_values[i + 1]  # 下降扣分（前值更大）
        end

        score.clamp(-90, 90)
      end

      # 计算现金占总资产比率分数（0-100分）
      # 近5年现金占总资产比率平均值，≥20%得100分，≥10%得50分
      def calculate_cash_ratio_score(all_data)
        cr_values = all_data.map { |d| d[:cash_to_assets_ratio] }.compact.map(&:to_f)
        return 0 if cr_values.size < 3

        avg_cr = cr_values.sum / cr_values.size

        case
        when avg_cr >= 20 then 100  # 现金充裕，抗风险能力强
        when avg_cr >= 10 then 50   # 现金充足
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