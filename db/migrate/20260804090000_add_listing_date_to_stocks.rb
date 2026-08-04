class AddListingDateToStocks < ActiveRecord::Migration[7.1]
  def change
    add_column :stocks, :listing_date, :date, comment: "上市日期（用于次新股标签）"
    add_index :stocks, [:market, :listing_date], name: "idx_stocks_market_listing_date"
  end
end
