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
      # 将 BRK.B → BRK_B，避免 URL 中点被 Rails 解释为格式后缀
      "#{exchange_name}-#{symbol.tr('.', '_')}"
    end
  end

  # 毛利率：统一使用财务指标表中已存储的 gross_margin 字段
  def calculate_gross_margin(_income_statement, financial_indicator)
    financial_indicator&.gross_margin
  end

  # 净利率：统一使用财务指标表中已存储的 net_sales_rate 字段
  def calculate_net_profit_margin(_income_statement, financial_indicator)
    financial_indicator&.net_sales_rate
  end

  def calculate_net_income(income_statement)
    income_statement&.net_income_to_shareholders
  end

  # 负债占资产比率：统一使用财务指标表中已存储的 asset_liab_ratio 字段
  def calculate_asset_liab_ratio(balance_sheet, financial_indicator = nil)
    financial_indicator&.asset_liab_ratio
  end

  # ROA(总资产收益率)：归母净利润 / 总资产
  def calculate_roa(income_statement, balance_sheet)
    return nil unless income_statement && balance_sheet
    return nil unless income_statement.net_income_to_shareholders.present?
    return nil unless balance_sheet.total_assets.present? && balance_sheet.total_assets != 0

    (income_statement.net_income_to_shareholders.to_f / balance_sheet.total_assets.to_f) * 100
  end

  # ROE(净资产收益率)：归母净利润 / 平均股东权益 * 100
  # 使用平均股东权益（期初+期末/2）计算，更符合行业标准
  def calculate_roe(income_statement, balance_sheet)
    return nil unless income_statement && balance_sheet
    return nil unless income_statement.net_income_to_shareholders.present?
    return nil unless balance_sheet.total_equity.present? && balance_sheet.total_equity != 0

    current_year = balance_sheet.report_date.year
    # 优先使用预加载集合，避免不必要的 DB 查询；按 report_date 排序取最新一条
    balance_collection = (preloaded_balance_sheets.presence || balance_sheets).to_a
    prev_balance = balance_collection
      .select { |bs| bs.report_date.year == current_year - 1 }
      .sort_by(&:report_date)
      .last

    if prev_balance && prev_balance.total_equity.present? && prev_balance.total_equity != 0
      avg_equity = (balance_sheet.total_equity.to_f + prev_balance.total_equity.to_f) / 2
    else
      avg_equity = balance_sheet.total_equity.to_f
    end

    (income_statement.net_income_to_shareholders.to_f / avg_equity) * 100
  end

  def calculate_asset_turnover_ratio(income_statement, balance_sheet)
    return nil unless income_statement && balance_sheet
    return nil unless balance_sheet.total_assets.present? && balance_sheet.total_assets != 0
    return nil unless income_statement.total_revenue.present?

    income_statement.total_revenue.to_f / balance_sheet.total_assets.to_f
  end

  # 现金占总资产比率：现金及现金等价物 / 总资产
  def calculate_cash_to_assets_ratio(balance_sheet)
    return nil unless balance_sheet
    return nil unless balance_sheet.cash_and_cash_equivalents.present? && balance_sheet.total_assets.present? && balance_sheet.total_assets != 0

    (balance_sheet.cash_and_cash_equivalents.to_f / balance_sheet.total_assets.to_f) * 100
  end

  # 应收账款周转率(次)：营业收入 / 应收账款
  def calculate_receivable_turnover(income_statement, balance_sheet)
    return nil unless income_statement && balance_sheet
    return nil unless income_statement.total_revenue.present?
    return nil unless balance_sheet.accounts_receivable.present? && balance_sheet.accounts_receivable != 0

    income_statement.total_revenue.to_f / balance_sheet.accounts_receivable.to_f
  end

  # 平均收现日数：365 / (营业收入 / 应收账款)
  def calculate_avg_collection_days(income_statement, balance_sheet)
    turnover = calculate_receivable_turnover(income_statement, balance_sheet)
    return nil unless turnover.present? && turnover != 0

    365.0 / turnover
  end

  # 固定资产周转率(次)：固定资产 / 营业收入
  def calculate_fixed_asset_turnover(income_statement, balance_sheet)
    return nil unless income_statement && balance_sheet
    return nil unless income_statement.total_revenue.present? && income_statement.total_revenue != 0
    return nil unless balance_sheet.property_plant_equipment.present?

    balance_sheet.property_plant_equipment.to_f / income_statement.total_revenue.to_f
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
      asset_liab_ratio: calculate_asset_liab_ratio(balance, indicator),
      asset_turnover_ratio: calculate_asset_turnover_ratio(income, balance),
      # 财务结构
      cash_to_assets_ratio: calculate_cash_to_assets_ratio(balance),
      # 经营能力
      receivable_turnover: calculate_receivable_turnover(income, balance),
      avg_collection_days: calculate_avg_collection_days(income, balance),
      fixed_asset_turnover: calculate_fixed_asset_turnover(income, balance),
      # 现金流量表
      cash_and_cash_equivalents: balance&.cash_and_cash_equivalents,
      operating_cash_flow: cash&.operating_cash_flow,
      investing_cash_flow: cash&.investing_cash_flow,
      financing_cash_flow: cash&.financing_cash_flow,
      net_cash_change: cash&.net_cash_change,
      roe: indicator&.roe_avg || calculate_roe(income, balance),
      roa: calculate_roa(income, balance),
      eps: indicator&.basic_eps,
      cash_flow_ps: indicator&.ncf_from_oa_ps,
      operating_margin: indicator&.operating_margin
    }
  end

  def financial_years
    # 只从 financial_indicators 表获取年份（四张表中数据最核心的表）
    # 避免其他表有数据但指标表缺失时，页面显示全是空值的列
    dates = if preloaded_income_statements.present?
      preloaded_financial_indicators&.map(&:report_date) || []
    else
      financial_indicators.pluck(:report_date)
    end
    dates.compact.map { |d| d.strftime('%Y') }.uniq.sort.reverse.first(8).sort
  end

  def get_radar_data
    latest_data = get_financial_data_by_year(financial_years.last)
    return nil unless latest_data

    {
      roe: latest_data[:roe],
      gross_margin: latest_data[:gross_margin],
      net_profit_margin: latest_data[:net_profit_margin],
      eps: latest_data[:eps],
      cash_to_assets_ratio: latest_data[:cash_to_assets_ratio],
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
