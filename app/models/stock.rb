class Stock < ApplicationRecord
  has_many :financial_reports
  has_many :income_statements, through: :financial_reports
  has_many :balance_sheets, through: :financial_reports
  has_many :cash_flows, through: :financial_reports
  has_many :financial_indicators, through: :financial_reports

  def to_param
    if market == 'CN'
      symbol
    else
      exchange_name = exchange.present? ? exchange.gsub('证券交易所', '').strip.upcase : 'NASDAQ'
      "#{exchange_name}-#{symbol}"
    end
  end
end
