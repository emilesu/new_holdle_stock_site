class Stock < ApplicationRecord
  include CacheableFinancialData

  has_many :user_favorites, dependent: :destroy
  has_many :favorite_users, through: :user_favorites, source: :user
  has_many :financial_reports
  has_many :income_statements, through: :financial_reports
  has_many :balance_sheets, through: :financial_reports
  has_many :cash_flows, through: :financial_reports
  has_many :financial_indicators, through: :financial_reports
  
  attr_accessor :preloaded_income_statements, :preloaded_balance_sheets, :preloaded_cash_flows, :preloaded_financial_indicators

  def financial_data_complete?
    income_statements.exists? && balance_sheets.exists? && cash_flows.exists? && financial_indicators.exists?
  end

  def to_param
    if market == 'CN'
      symbol
    elsif market == 'HK'
      "HK#{symbol.sub(/\.HK\z/, '')}"
    else
      exchange_name = exchange.present? ? exchange.gsub('证券交易所', '').strip.upcase : 'NASDAQ'
      "#{exchange_name}-#{symbol}"
    end
  end

  def calculate_gross_margin(income_statement, financial_indicator)
    return nil unless financial_indicator || income_statement

    if market == 'CN'
      financial_indicator&.gross_margin
    else
      return nil unless income_statement
      return nil unless income_statement.total_revenue.present? && income_statement.total_revenue != 0
      return nil unless income_statement.operating_income.present?

      (income_statement.operating_income.to_f / income_statement.total_revenue.to_f) * 100
    end
  end

  def calculate_net_profit_margin(income_statement, financial_indicator)
    return nil unless financial_indicator || income_statement

    if market == 'CN'
      return nil unless income_statement
      return nil unless income_statement.total_revenue.present? && income_statement.total_revenue != 0
      return nil unless income_statement.net_income_to_shareholders.present?

      (income_statement.net_income_to_shareholders.to_f / income_statement.total_revenue.to_f) * 100
    else
      financial_indicator&.net_sales_rate
    end
  end

  def calculate_net_income(income_statement)
    income_statement&.net_income_to_shareholders
  end

  def calculate_asset_liab_ratio(balance_sheet)
    return nil unless balance_sheet
    return nil unless balance_sheet.total_assets.present? && balance_sheet.total_assets != 0
    return nil unless balance_sheet.total_liabilities.present?

    (balance_sheet.total_liabilities.to_f / balance_sheet.total_assets.to_f) * 100
  end

  def calculate_asset_turnover_ratio(income_statement, balance_sheet)
    return nil unless income_statement && balance_sheet
    return nil unless balance_sheet.total_assets.present? && balance_sheet.total_assets != 0
    return nil unless income_statement.total_revenue.present?

    income_statement.total_revenue.to_f / balance_sheet.total_assets.to_f
  end

  def get_financial_data_by_year(year)
    year_str = year.to_s
    
    income_collection = preloaded_income_statements.presence || income_statements
    balance_collection = preloaded_balance_sheets.presence || balance_sheets
    cash_collection = preloaded_cash_flows.presence || cash_flows
    indicator_collection = preloaded_financial_indicators.presence || financial_indicators
    
    income = income_collection.detect { |i| i.report_date&.strftime('%Y') == year_str }
    balance = balance_collection.detect { |b| b.report_date&.strftime('%Y') == year_str }
    cash = cash_collection.detect { |c| c.report_date&.strftime('%Y') == year_str }
    indicator = indicator_collection.detect { |i| i.report_date&.strftime('%Y') == year_str }

    {
      year: year,
      income_statement: income,
      balance_sheet: balance,
      cash_flow: cash,
      indicator: indicator,
      gross_margin: calculate_gross_margin(income, indicator),
      net_profit_margin: calculate_net_profit_margin(income, indicator),
      net_income: calculate_net_income(income),
      asset_liab_ratio: calculate_asset_liab_ratio(balance),
      asset_turnover_ratio: calculate_asset_turnover_ratio(income, balance),
      operating_cash_flow: cash&.operating_cash_flow,
      investing_cash_flow: cash&.investing_cash_flow,
      financing_cash_flow: cash&.financing_cash_flow,
      net_cash_change: cash&.net_cash_change,
      roe: indicator&.roe_avg,
      roa: indicator&.net_interest_of_ta,
      eps: indicator&.basic_eps,
      cash_flow_ps: indicator&.ncf_from_oa_ps,
      operating_margin: indicator&.operating_margin
    }
  end

  def financial_years
    if preloaded_income_statements.present?
      dates = []
      dates += preloaded_income_statements.map(&:report_date)
      dates += preloaded_balance_sheets.map(&:report_date) if preloaded_balance_sheets
      dates += preloaded_cash_flows.map(&:report_date) if preloaded_cash_flows
      dates += preloaded_financial_indicators.map(&:report_date) if preloaded_financial_indicators
      dates.compact.map { |d| d.strftime('%Y') }.uniq.sort.reverse.first(8).sort
    else
      dates = []
      dates += income_statements.pluck(:report_date)
      dates += balance_sheets.pluck(:report_date)
      dates += cash_flows.pluck(:report_date)
      dates += financial_indicators.pluck(:report_date)
      dates.compact.map { |d| d.strftime('%Y') }.uniq.sort.reverse.first(8).sort
    end
  end

  def get_radar_data
    latest_data = get_financial_data_by_year(financial_years.last)
    return nil unless latest_data

    {
      roe: latest_data[:roe],
      gross_margin: latest_data[:gross_margin],
      net_profit_margin: latest_data[:net_profit_margin],
      eps: latest_data[:eps],
      asset_liab_ratio: latest_data[:asset_liab_ratio],
      asset_turnover_ratio: latest_data[:asset_turnover_ratio]
    }
  end

  def five_year_roe_average
    recent_years = financial_years.last(5)
    return nil if recent_years.size < 3

    roe_values = recent_years.map do |year|
      data = get_financial_data_by_year(year)
      data[:roe]
    end.compact

    return nil if roe_values.empty?

    roe_values.sum / roe_values.size
  end

  def display_name_for_comparison
    return name if name.blank?

    if market == 'US'
      parts = name.split('|')
      return parts.first.strip if parts.size >= 2
    end

    name
  end
end
