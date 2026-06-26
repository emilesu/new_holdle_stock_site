module DataSources
  # 单股雷达数据预计算服务
  # 计算6项独立雷达指标，归一化后存入数据库供前端高频读取
  # 数据来源统一使用 Stock#get_financial_data_by_year（与金字塔评分一致）
  class StockRadarSingleService
    # 各指标归一化最大值配置
    MAX_VALUES = {
      roe: 100,                    # ROE最大值100%
      gross_margin: 100,           # 毛利率最大值100%
      net_profit_margin: 100,      # 净利率最大值100%
      eps: 20,                     # EPS最大值20元
      cash_to_assets_ratio: 100,   # 现金占总资产比率最大值100%
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
          financial_years = stock.financial_years.select { |y| y.to_i >= Date.current.year - 5 }.sort.last(5)
          return { success: false, error: '财务数据不足' } if financial_years.empty?

          # 统一使用 Stock#get_financial_data_by_year 获取预计算指标
          all_data = financial_years.map { |year| stock.get_financial_data_by_year(year) }.compact
          return { success: false, error: '财务数据为空' } if all_data.empty?

          # 计算原始值并归一化
          raw_values = calculate_raw_values(all_data)
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

      # 计算原始财务指标值（取近5年平均值）
      # 数据来自 Stock#get_financial_data_by_year 的预计算字段，与详情页展示一致
      def calculate_raw_values(all_data)
        {
          roe: avg_value(all_data, :roe),
          gross_margin: avg_value(all_data, :gross_margin),
          net_profit_margin: avg_value(all_data, :net_profit_margin),
          eps: avg_value(all_data, :eps),
          cash_to_assets_ratio: avg_value(all_data, :cash_to_assets_ratio),
          asset_turnover_ratio: avg_value(all_data, :asset_turnover_ratio)
        }
      end

      # 从预计算数据中提取指定字段的平均值
      def avg_value(all_data, key)
        values = all_data.map { |d| d[key] }.compact.map(&:to_f).reject(&:zero?)
        values.empty? ? nil : values.sum / values.size
      end

      # 归一化所有指标值到0-100分
      def normalize_values(raw_values)
        {
          roe: normalize(raw_values[:roe], MAX_VALUES[:roe]),
          gross_margin: normalize(raw_values[:gross_margin], MAX_VALUES[:gross_margin]),
          net_profit_margin: normalize(raw_values[:net_profit_margin], MAX_VALUES[:net_profit_margin]),
          eps: normalize(raw_values[:eps], MAX_VALUES[:eps]),
          cash_to_assets_ratio: normalize(raw_values[:cash_to_assets_ratio], MAX_VALUES[:cash_to_assets_ratio]),
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

      # 获取全零默认值（异常时使用）
      def default_zero_values
        {
          'roe' => 0,
          'gross_margin' => 0,
          'net_profit_margin' => 0,
          'eps' => 0,
          'cash_to_assets_ratio' => 0,
          'asset_turnover_ratio' => 0
        }
      end
    end
  end
end