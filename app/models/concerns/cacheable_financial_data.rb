module CacheableFinancialData
  extend ActiveSupport::Concern

  included do
    def cached_financial_data
      Rails.cache.fetch([self, :financial_data, updated_at.to_i], expires_in: 1.hour) do
        data = {}
        financial_years.each do |year|
          data[year] = get_financial_data_by_year(year)
        end
        data
      end
    end

    def cached_five_year_roe
      Rails.cache.fetch([self, :five_year_roe, updated_at.to_i], expires_in: 24.hours) do
        five_year_roe_average
      end
    end

    def cached_radar_data
      Rails.cache.fetch([self, :radar_data, updated_at.to_i], expires_in: 6.hours) do
        StockRadarDataService.call(self)
      end
    end
  end
end