module DataSources
  # 金字塔分数计算服务
  # 依据金字塔8项打分规则计算股票总分，仅存储累加后的总分
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
            { success: true, old_score: old_score, new_score: new_score, error: nil, updated: false }
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

      # 计算金字塔总分（8项指标累加）
      # @param stock [Stock] 股票对象
      # @param all_data [Array] 近5年财务数据
      # @return [Integer] 总分（0-1000分）
      def calculate_total_score(stock)
        score = 0
        
        financial_years = stock.financial_years.select { |y| y.to_i >= Date.current.year - 5 }.sort.last(5)
        return 0 if financial_years.empty?

        all_data = financial_years.map { |year| stock.get_financial_data_by_year(year) }.compact
        return 0 if all_data.empty?

        score += calculate_roe_score(all_data)           # ROE分数（核心指标，权重最高）
        score += calculate_roa_score(all_data)           # ROA分数
        score += calculate_net_income_score(all_data)    # 净利润规模分数
        score += calculate_asset_turnover_score(all_data) # 资产周转率分数
        score += calculate_gross_margin_score(stock, all_data) # 毛利率分数
        score += calculate_net_profit_growth_score(stock, all_data) # 净利润增长率分数
        score += calculate_cash_flow_growth_score(all_data) # 经营现金流增长分数
        
        score.clamp(0, 1000)
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
          score += weights[idx] if ni_values[i] > ni_values[i + 1]  # 增长加分
          score -= weights[idx] if ni_values[i] < ni_values[i + 1]  # 下降扣分
        end

        score.clamp(-90, 90)
      end

      # 计算经营现金流增长分数（-35至35分）
      def calculate_cash_flow_growth_score(all_data)
        cf_values = all_data.map { |d| d[:operating_cash_flow] }.compact.map(&:to_f)
        return 0 if cf_values.size < 5

        score = 0
        years = [0, 1, 2, 3]     # 最近4年对比
        weights = [30, 25, 20, 15] # 权重递减

        years.each_with_index do |i, idx|
          next if i + 1 >= cf_values.size
          score += weights[idx] if cf_values[i] > cf_values[i + 1]
          score -= weights[idx] if cf_values[i] < cf_values[i + 1]
        end

        score.clamp(-35, 35)
      end

      # 更新股票金字塔分数
      def update_stock(stock, score)
        stock.update!(
          pyramid_total_score: score,
          last_pyramid_calc_at: Time.current
        )
      end
    end
  end
end