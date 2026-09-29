class StockMonthlyBar < ApplicationRecord
  belongs_to :stock

  # 按交易日升序（图表与 MACD 递推均按时间正序）
  scope :chronological, -> { order(:trade_date) }
end