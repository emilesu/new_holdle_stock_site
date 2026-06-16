module StockRadarDataService
  MAX_VALUES = {
    roe: 100,
    gross_margin: 100,
    net_profit_margin: 100,
    eps: 20,
    asset_liab_ratio: 100,
    asset_turnover_ratio: 2
  }.freeze

  class << self
    def call(stock)
      recent_years = stock.financial_years.last(5)
      return nil if recent_years.empty?

      all_data = recent_years.map { |year| stock.get_financial_data_by_year(year) }.compact

      return nil if all_data.empty?

      raw_values = calculate_average(all_data)

      {
        symbol: stock.symbol,
        name: stock.name,
        display_name: format_display_name(stock),
        year: "#{recent_years.min}-#{recent_years.max}",
        raw_values: raw_values,
        normalized_values: normalize_values(raw_values)
      }
    end

    def batch_call(stocks)
      result = {}
      stocks.each do |stock|
        data = call(stock)
        result[stock.symbol] = data if data
      end
      result
    end

    private

    def calculate_average(data_array)
      {
        roe: average_values(data_array, :roe),
        gross_margin: average_values(data_array, :gross_margin),
        net_profit_margin: average_values(data_array, :net_profit_margin),
        eps: average_values(data_array, :eps),
        asset_liab_ratio: average_values(data_array, :asset_liab_ratio),
        asset_turnover_ratio: average_values(data_array, :asset_turnover_ratio)
      }
    end

    def average_values(data_array, key)
      values = data_array.map { |d| d[key] }.compact.map(&:to_f).reject(&:zero?)
      values.empty? ? nil : values.sum / values.size
    end

    private

    def normalize_values(raw_values)
      {
        roe: normalize(raw_values[:roe], MAX_VALUES[:roe]),
        gross_margin: normalize(raw_values[:gross_margin], MAX_VALUES[:gross_margin]),
        net_profit_margin: normalize(raw_values[:net_profit_margin], MAX_VALUES[:net_profit_margin]),
        eps: normalize(raw_values[:eps], MAX_VALUES[:eps]),
        asset_liab_ratio: normalize_reverse(raw_values[:asset_liab_ratio], MAX_VALUES[:asset_liab_ratio]),
        asset_turnover_ratio: normalize(raw_values[:asset_turnover_ratio], MAX_VALUES[:asset_turnover_ratio])
      }
    end

    def normalize(value, max_value)
      return 0 if value.blank?

      score = (value.to_f / max_value) * 100
      score.clamp(0, 100)
    end

    def normalize_reverse(value, max_value)
      return 0 if value.blank?

      score = (1 - value.to_f / max_value) * 100
      score.clamp(0, 100)
    end

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