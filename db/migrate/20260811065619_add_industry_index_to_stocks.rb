class AddIndustryIndexToStocks < ActiveRecord::Migration[7.1]
  def change
    add_index :stocks, [:market, :sector, :industry, :pyramid_total_score],
              name: "index_stocks_on_market_sector_industry_pyramid_total_score"
  end
end
