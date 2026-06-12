class Stock < ApplicationRecord
  has_many :financial_reports
  has_many :income_statements, through: :financial_reports
  has_many :balance_sheets, through: :financial_reports
  has_many :cash_flows, through: :financial_reports
  has_many :financial_indicators, through: :financial_reports
end
