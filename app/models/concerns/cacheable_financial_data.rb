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

    # 详情页财务列表：近 20 年年报 + 右侧同比两列（左=去年同期同一期次，右=最近一期定期报告）
    # v2：结构由「年份 => 数据」升级为 { annual:, quarters: }，并纳入季报口径，升级版本号避免命中旧缓存
    def cached_detail_financials
      Rails.cache.fetch([self, :financial_detail, "v2", updated_at.to_i], expires_in: 1.hour) do
        annual = {}
        financial_years.each do |year|
          annual[year] = get_financial_data_by_year(year)
        end

        quarters = period_comparison_periods.map do |period|
          {
            label: period_label(period.period_type, period.report_date),
            period_type: period.period_type,
            report_date: period.report_date,
            data: get_financial_data_by_period(period.period_type, period.report_date)
          }
        end

        { annual: annual, quarters: quarters }
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