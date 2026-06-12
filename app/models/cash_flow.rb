class CashFlow < ApplicationRecord
  belongs_to :financial_report
  belongs_to :stock

  validates :financial_report_id, presence: true
  validates :stock_id, presence: true
  validates :report_date, presence: true
  validates :market, presence: true
end