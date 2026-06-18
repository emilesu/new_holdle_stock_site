class FinancialIndicator < ApplicationRecord
  belongs_to :financial_report
  belongs_to :stock
end
