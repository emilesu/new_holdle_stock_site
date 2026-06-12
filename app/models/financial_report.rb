class FinancialReport < ApplicationRecord
  belongs_to :stock
  has_many :income_statements
  has_many :balance_sheets
  has_many :cash_flows
end
