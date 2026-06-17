module DataSources
  # 雷达对比服务
  # 用于前台双股雷达图对比，优先读取缓存，缺失时实时计算兜底
  class StockRadarCompareService
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
      # @param base_stock [Stock] 基准股票（通常为行业第一）
      # @param compare_stock [Stock, nil] 对比股票（悬浮选中的股票）
      # @return [Hash] 对比数据 { base: Hash, compare: Hash }
      def call(base_stock, compare_stock = nil)
        base_data = get_radar_data(base_stock)

        # 获取对比股票数据（排除与基准股票相同的情况）
        compare_data = if compare_stock && compare_stock.id != base_stock.id
          get_radar_data(compare_stock)
        else
          nil
        end

        {
          base: {
            symbol: base_stock.symbol,
            name: base_stock.name,
            display_name: format_display_name(base_stock),
            values: base_data
          },
          compare: compare_data ? {
            symbol: compare_stock.symbol,
            name: compare_stock.name,
            display_name: format_display_name(compare_stock),
            values: compare_data
          } : nil
        }
      end

      private

      # 获取股票雷达数据（优先从缓存读取，缺失时实时计算）
      # @param stock [Stock] 股票对象
      # @return [Hash] 6维度归一化分数
      def get_radar_data(stock)
        return default_zero_values unless stock

        # 优先使用缓存
        if stock.radar_dim_scores.present? && stock.radar_dim_scores.keys.size >= 6
          return stock.radar_dim_scores
        end

        # 缓存缺失，实时计算兜底（使用与StockRadarSingleService相同的计算逻辑）
        begin
          financial_years = stock.financial_years.select { |y| y.to_i >= Date.today.year - 5 }.sort.last(5)
          return default_zero_values if financial_years.empty?

          # 获取财务数据
          all_data = financial_years.map { |year| get_financial_data(stock, year) }.compact
          return default_zero_values if all_data.empty?

          # 计算原始值（使用修正后的计算逻辑）
          raw_values = calculate_raw_values(all_data, stock.market)

          # 归一化并转换为字符串键
          normalize_values(raw_values).stringify_keys
        rescue => e
          Rails.logger.error "StockRadarCompareService fallback error for #{stock.symbol}: #{e.message}"
          default_zero_values
        end
      end

      # 获取股票指定年份的财务数据
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
      def normalize_asset_turnover(value)
        return 0 if value.blank?

        ratio = value.to_f * 100
        score = ratio.clamp(0, 100)
        score
      end

      # 正向归一化
      def normalize(value, max_value)
        return 0 if value.blank?

        score = (value.to_f / max_value) * 100
        score.clamp(0, 100)
      end

      # 反向归一化（负债比率越低分数越高）
      def normalize_reverse(value, max_value)
        return 0 if value.blank?

        ratio = value.to_f / max_value
        score = (1 - ratio) * 100
        score.clamp(0, 100)
      end

      # 获取全零默认值
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

      # 格式化股票显示名称
      def format_display_name(stock)
        return stock.name if stock.name.blank?

        if stock.market == 'US'
          parts = stock.name.split('|')
          return parts.first.strip if parts.size >= 2
        end

        stock.name
      end
    end
  end
end