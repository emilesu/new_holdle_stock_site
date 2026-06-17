module DataSources
  # 单股雷达数据预计算服务
  # 计算6项独立雷达指标，归一化后存入数据库供前端高频读取
  class StockRadarSingleService
    # 各指标归一化最大值配置
    MAX_VALUES = {
      roe: 100,                    # ROE最大值100%
      gross_margin: 100,           # 毛利率最大值100%
      net_profit_margin: 100,      # 净利率最大值100%
      eps: 20,                     # EPS最大值20元
      asset_liab_ratio: 100,       # 负债比率最大值100%
      asset_turnover_ratio: 2      # 资产周转率最大值（仅供参考，使用专用方法）
    }.freeze

    class << self
      # 主入口方法
      # @param stock [Stock] 股票对象
      # @return [Hash] 计算结果 { success: Boolean, updated: Boolean, values: Hash, error: String }
      def call(stock)
        return { success: false, error: '股票不存在' } unless stock

        begin
          # 获取近5年财务年份
          financial_years = stock.financial_years.select { |y| y.to_i >= Date.today.year - 5 }.sort.last(5)
          return { success: false, error: '财务数据不足' } if financial_years.empty?

          # 获取财务数据（需要income_statement和balance_sheet用于计算）
          all_data = financial_years.map { |year| get_financial_data(stock, year) }.compact
          return { success: false, error: '财务数据为空' } if all_data.empty?

          # 计算原始值并归一化（使用修正后的计算逻辑）
          raw_values = calculate_raw_values(all_data, stock.market)
          normalized_values = normalize_values(raw_values)

          # 幂等性检测：比较新旧分数
          old_scores = stock.radar_dim_scores || {}
          new_scores = normalized_values.stringify_keys

          if old_scores == new_scores
            { success: true, updated: false, values: new_scores }
          else
            stock.update!(radar_dim_scores: new_scores)
            { success: true, updated: true, values: new_scores }
          end
        rescue => e
          Rails.logger.error "StockRadarSingleService error for #{stock.symbol}: #{e.message}"
          stock.update!(radar_dim_scores: default_zero_values)
          { success: false, error: e.message, values: default_zero_values }
        end
      end

      private

      # 获取股票指定年份的财务数据
      # @param stock [Stock] 股票对象
      # @param year [Integer] 年份
      # @return [Hash, nil] 包含income_statement、balance_sheet和indicator的完整数据
      def get_financial_data(stock, year)
        year_str = year.to_s
        
        income = stock.income_statements.detect { |i| i.report_date&.strftime('%Y') == year_str }
        balance = stock.balance_sheets.detect { |b| b.report_date&.strftime('%Y') == year_str }
        indicator = stock.financial_indicators.detect { |i| i.report_date&.strftime('%Y') == year_str }

        return nil unless income || balance || indicator

        {
          year: year,
          income_statement: income,
          balance_sheet: balance,
          indicator: indicator
        }
      end

      # 计算原始财务指标值（取近5年平均值，根据市场类型使用不同计算逻辑）
      # 修正规则：
      # 1. 毛利率：A股直接用字段gross_margin，美股计算operating_income / total_revenue
      # 2. 净利率：A股计算net_income_to_shareholders / total_revenue，美股直接用字段net_sales_rate
      # 3. 总资产周转率：计算total_revenue / total_assets
      # 4. 负债占资产比率：计算total_liabilities / total_assets
      def calculate_raw_values(all_data, market)
        {
          roe: average_values(all_data) { |d| d[:indicator]&.roe_avg },
          gross_margin: calculate_gross_margin_avg(all_data, market),
          net_profit_margin: calculate_net_profit_margin_avg(all_data, market),
          eps: average_values(all_data) { |d| d[:indicator]&.basic_eps },
          asset_liab_ratio: calculate_asset_liab_ratio_avg(all_data),
          asset_turnover_ratio: calculate_asset_turnover_ratio_avg(all_data)
        }
      end

      # 计算毛利率平均值
      # A股：直接使用indicator的gross_margin字段
      # 美股：计算 operating_income / total_revenue
      def calculate_gross_margin_avg(all_data, market)
        values = all_data.map do |d|
          next nil unless d[:income_statement]

          if market == 'CN'
            d[:indicator]&.gross_margin
          else
            # 美股：operating_income / total_revenue
            operating_income = d[:income_statement].operating_income.to_f
            total_revenue = d[:income_statement].total_revenue.to_f
            total_revenue > 0 ? (operating_income / total_revenue) * 100 : nil
          end
        end.compact.map(&:to_f).reject(&:zero?)

        values.empty? ? nil : values.sum / values.size
      end

      # 计算净利率平均值
      # A股：计算 net_income_to_shareholders / total_revenue
      # 美股：直接使用indicator的net_sales_rate字段
      def calculate_net_profit_margin_avg(all_data, market)
        values = all_data.map do |d|
          next nil unless d[:income_statement]

          if market == 'CN'
            # A股：net_income_to_shareholders / total_revenue
            net_income = d[:income_statement].net_income_to_shareholders.to_f
            total_revenue = d[:income_statement].total_revenue.to_f
            total_revenue > 0 ? (net_income / total_revenue) * 100 : nil
          else
            d[:indicator]&.net_sales_rate
          end
        end.compact.map(&:to_f).reject(&:zero?)

        values.empty? ? nil : values.sum / values.size
      end

      # 计算负债占资产比率平均值
      # 计算公式：total_liabilities / total_assets
      def calculate_asset_liab_ratio_avg(all_data)
        values = all_data.map do |d|
          next nil unless d[:balance_sheet]

          total_liabilities = d[:balance_sheet].total_liabilities.to_f
          total_assets = d[:balance_sheet].total_assets.to_f
          total_assets > 0 ? (total_liabilities / total_assets) * 100 : nil
        end.compact.map(&:to_f).reject(&:zero?)

        values.empty? ? nil : values.sum / values.size
      end

      # 计算总资产周转率平均值
      # 计算公式：total_revenue / total_assets
      def calculate_asset_turnover_ratio_avg(all_data)
        values = all_data.map do |d|
          next nil unless d[:income_statement] && d[:balance_sheet]

          total_revenue = d[:income_statement].total_revenue.to_f
          total_assets = d[:balance_sheet].total_assets.to_f
          total_assets > 0 ? total_revenue / total_assets : nil
        end.compact.map(&:to_f).reject(&:zero?)

        values.empty? ? nil : values.sum / values.size
      end

      # 通用平均值计算方法
      # @param data_array [Array] 数据数组
      # @param block [Proc] 提取值的块
      # @return [Float, nil] 平均值或nil
      def average_values(data_array, &block)
        values = data_array.map(&block).compact.map(&:to_f).reject(&:zero?)
        values.empty? ? nil : values.sum / values.size
      end

      # 归一化所有指标值到0-100分
      def normalize_values(raw_values)
        {
          roe: normalize(raw_values[:roe], MAX_VALUES[:roe]),
          gross_margin: normalize(raw_values[:gross_margin], MAX_VALUES[:gross_margin]),
          net_profit_margin: normalize(raw_values[:net_profit_margin], MAX_VALUES[:net_profit_margin]),
          eps: normalize(raw_values[:eps], MAX_VALUES[:eps]),
          asset_liab_ratio: normalize_reverse(raw_values[:asset_liab_ratio], MAX_VALUES[:asset_liab_ratio]),
          asset_turnover_ratio: normalize_asset_turnover(raw_values[:asset_turnover_ratio])
        }
      end

      # 资产周转率专用归一化方法
      # 资产周转率范围通常在0-2之间，需先转换为百分比再归一化
      def normalize_asset_turnover(value)
        return 0 if value.blank?

        ratio = value.to_f * 100  # 转换为百分比
        score = ratio.clamp(0, 100)
        score
      end

      # 正向归一化（值越高分数越高）
      # @param value [Float] 原始值
      # @param max_value [Float] 最大值
      # @return [Float] 归一化分数(0-100)
      def normalize(value, max_value)
        return 0 if value.blank?

        score = (value.to_f / max_value) * 100
        score.clamp(0, 100)
      end

      # 反向归一化（值越低分数越高，用于负债比率等）
      # 负债比率越低，说明财务结构越稳健，分数越高
      # @param value [Float] 原始值
      # @param max_value [Float] 最大值
      # @return [Float] 归一化分数(0-100)
      def normalize_reverse(value, max_value)
        return 0 if value.blank?

        ratio = value.to_f / max_value
        score = (1 - ratio) * 100
        score.clamp(0, 100)
      end

      # 获取全零默认值（异常时使用）
      def default_zero_values
        {
          'roe' => 0,
          'gross_margin' => 0,
          'net_profit_margin' => 0,
          'eps' => 0,
          'asset_liab_ratio' => 0,
          'asset_turnover_ratio' => 0
        }
      end
    end
  end
end