class Stock < ApplicationRecord
  include CacheableFinancialData

  # 详情页年报列上限（方案：展示最近 20 年年报，不足则全显示）
  MAX_ANNUAL_YEARS = 20
  # 期次中文标签（annual/q1/h1/q3，累计口径）
  PERIOD_TYPE_LABELS = { "annual" => "年报", "q1" => "一季报", "h1" => "中报", "q3" => "三季报" }.freeze

  has_many :user_favorites, dependent: :destroy
  has_many :favorite_users, through: :user_favorites, source: :user
  has_many :financial_reports
  has_many :income_statements, through: :financial_reports
  has_many :balance_sheets, through: :financial_reports
  has_many :cash_flows, through: :financial_reports
  has_many :financial_indicators, through: :financial_reports

  # 新收录股票 → 异步推送给百度（新 URL 对 SEO 价值最高；失败不影响入库）
  after_commit :push_to_baidu_on_create, on: :create, if: -> { ENV["BAIDU_PUSH_TOKEN"].to_s.present? }
  
  attr_accessor :preloaded_income_statements, :preloaded_balance_sheets, :preloaded_cash_flows, :preloaded_financial_indicators

  def financial_data_complete?
    income_statements.exists? && balance_sheets.exists? && cash_flows.exists? && financial_indicators.exists?
  end

  # 金字塔列表警示标签（批量计算，纯展示用途，不参与评分）
  # 依赖预加载的财务数据（preloaded_* accessor），避免列表页 N+1 查询
  def self.pyramid_tags_for(stocks)
    stocks.map { |s| [s.id, s.pyramid_tags] }.to_h
  end

  # 预加载列表财务数据到模型 accessor，批量计算警示标签避免 N+1
  # 仅预加载 income_statements + financial_indicators 即可支撑 pyramid_tags；
  # 金字塔列表页与股票详情页对比栏共用，避免两处重复实现导致口径漂移
  def self.preload_pyramid_financials(stocks)
    ids = stocks.map(&:id)
    return if ids.empty?

    reports = FinancialReport.where(stock_id: ids).includes(:financial_indicators, :income_statements).group_by(&:stock_id)
    stocks.each do |s|
      rs = reports[s.id] || []
      # 仅装载年报口径：金字塔评分/警示标签只认年报，季报会污染近5年取数与评分
      incomes = rs.flat_map { |r| r.income_statements.to_a }.select { |i| i.period_type == "annual" }
      indicators = rs.flat_map { |r| r.financial_indicators.to_a }.select { |i| i.period_type == "annual" }
      # 无年报数据的股票用 [nil] 哨兵，确保 financial_years 走内存分支而非触发查询
      s.preloaded_income_statements = incomes.empty? ? [nil] : incomes
      s.preloaded_financial_indicators = indicators.empty? ? [nil] : indicators
    end
  end

  # 标签悬停提示文案（金字塔列表徽章 title）
  def self.pyramid_tag_hint(tag)
    {
      '数据<5年' => '财务数据不足5年，评分可靠性较低',
      '亏损年份' => '近5年存在亏损年份，评分经特殊规则处理',
      '次新股'   => '上市不足3年，历史表现参考有限'
    }[tag] || tag
  end

  # 单只股票的金字塔警示标签（纯展示，不参与评分）
  # - "数据<5年": 财务指标不足5年，评分基于5年均值，可靠性较低
  # - "亏损年份": 近5年存在 ROE<=0 或净利润<0 的年份，增长/现金分经特殊规则处理
  # - "次新股": 上市日期距今不足3年（需 listing_date 已同步，美股暂不支持）
  def pyramid_tags
    years = financial_years.last(5)
    tags = []
    tags << '数据<5年' if years.size < 5
    tags << '亏损年份' if years.any? { |y| pyramid_loss_year?(y) }
    tags << '次新股' if new_listing?
    tags
  end

  # 次新股：上市日期距今不足 3 年（美股无上市日期数据，一律返回 false）
  def new_listing?
    listing_date.present? && listing_date <= Date.current && listing_date >= (Date.current - 3.years)
  end

  before_save :set_pinyin_initials

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

  # 年报口径财务数据（仅 annual）：金字塔评分、雷达图、近五年ROE 均依赖本方法
  def get_financial_data_by_year(year)
    year_str = year.to_s

    income_collection = preloaded_income_statements.presence || income_statements
    balance_collection = preloaded_balance_sheets.presence || balance_sheets
    cash_collection = preloaded_cash_flows.presence || cash_flows
    indicator_collection = preloaded_financial_indicators.presence || financial_indicators

    income = detect_annual_record(income_collection, year_str)
    balance = detect_annual_record(balance_collection, year_str)
    cash = detect_annual_record(cash_collection, year_str)
    indicator = detect_annual_record(indicator_collection, year_str)

    build_financial_data(
      year: year,
      label: year_str,
      period_type: "annual",
      report_date: income&.report_date || indicator&.report_date,
      income_statement: income,
      balance_sheet: balance,
      cash_flow: cash,
      indicator: indicator
    )
  end

  # 指定期次（季报/年报）的财务数据，用于详情页右侧同比两列
  def get_financial_data_by_period(period_type, report_date)
    return nil if period_type.blank? || report_date.blank?

    date = report_date.to_date
    income = income_statements.where(period_type: period_type, report_date: date).first
    balance = balance_sheets.where(period_type: period_type, report_date: date).first
    cash = cash_flows.where(period_type: period_type, report_date: date).first
    indicator = financial_indicators.where(period_type: period_type, report_date: date).first

    build_financial_data(
      year: nil,
      label: period_label(period_type, date),
      period_type: period_type,
      report_date: date,
      income_statement: income,
      balance_sheet: balance,
      cash_flow: cash,
      indicator: indicator
    )
  end

  # 最近一期季报（非年报，以财务指标表为主表，避免展示整列空值）
  def latest_quarter_period
    financial_indicators
      .where.not(period_type: "annual")
      .where.not(report_date: nil)
      .order(report_date: :desc, id: :desc)
      .first
  end

  # 去年同期同一期次：距 report_date - 1.year 最近的一条同 period_type 记录（容差 120 天，兼容非 12 月财年）
  def prior_year_same_period(period)
    return nil unless period&.report_date

    target = period.report_date - 1.year
    candidates = financial_indicators
      .where(period_type: period.period_type)
      .where(report_date: (target - 120.days)..(target + 120.days))
      .to_a
    candidates.min_by { |record| (record.report_date - target).abs }
  end

  # 详情页右侧同比两列：左=去年同期同一期次，右=最近一期季报
  # 无季报数据（如仅披露年报，或数据尚未重爬）时返回空数组，视图不出这两列
  def period_comparison_periods
    latest = latest_quarter_period
    return [] unless latest

    [ prior_year_same_period(latest), latest ].compact
  end

  # 近 N 期季报（非年报，累计口径），按报告期升序，用于季报趋势图
  # 期数上限直接复用抓取层保留策略常量，避免两处各写一个 16 造成漂移
  def recent_quarter_periods(limit = DataSources::Fetchers::BaseFetcher::MAX_QUARTERS_BACK)
    financial_indicators
      .where.not(period_type: "annual")
      .where.not(report_date: nil)
      .order(report_date: :desc)
      .limit(limit)
      .to_a
      .sort_by(&:report_date)
  end

  # 期次中文标签，如 2026中报 / 2025年报
  def period_label(period_type, report_date)
    return nil if report_date.blank?

    "#{report_date.year}#{PERIOD_TYPE_LABELS[period_type] || period_type}"
  end

  def financial_years
    # 只从 financial_indicators 表获取年份（四张表中数据最核心的表）
    # 避免其他表有数据但指标表缺失时，页面显示全是空值的列
    # 仅取年报口径（annual），季报由右侧同比两列单独展示
    if preloaded_income_statements.present?
      # 无财务数据股票 preload 时写入 [nil] 哨兵，需 compact 容错，避免对 nil 调用 report_date
      annual = preloaded_financial_indicators&.compact&.select { |i| i.period_type == "annual" }
      dates = annual&.map(&:report_date) || []
    else
      dates = financial_indicators.where(period_type: "annual").pluck(:report_date)
    end
    dates.compact.map { |d| d.strftime('%Y') }.uniq.sort.reverse.first(MAX_ANNUAL_YEARS).sort
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

  private

  # 在（可能已预加载的）集合中取指定年份的年报记录，兼容 [nil] 哨兵
  def detect_annual_record(collection, year_str)
    collection.detect { |record| record&.period_type == "annual" && record.report_date&.strftime('%Y') == year_str }
  end

  # 统一组装财务指标 hash：年报与季报共用，避免两处口径漂移
  def build_financial_data(income_statement:, balance_sheet:, cash_flow:, indicator:,
                           year: nil, label: nil, period_type: nil, report_date: nil)
    income = income_statement
    balance = balance_sheet
    cash = cash_flow

    {
      year: year,
      label: label,
      period_type: period_type,
      report_date: report_date,
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

  # 通知百度抓取新收录的股票详情页（异步、静默失败）
  def push_to_baidu_on_create
    BaiduPushJob.perform_later(["https://www.holdle.com/stocks/#{to_param}"])
  rescue => e
    Rails.logger.error "[Stock] 新股票推送百度失败 #{symbol}: #{e.message}"
  end

  def set_pinyin_initials
    self.pinyin_initials = if market.in?(%w[CN HK]) && name.present?
                             Pinyin.t(name).split.map(&:first).join.upcase
                           elsif market == 'US' && name.present? && name.include?('|')
                             chinese_part = name.split('|').first.strip
                             Pinyin.t(chinese_part).split.map(&:first).join.upcase
                           end
  end

  # 判断某年是否为亏损年份（ROE<=0 或净利润<0）
  def pyramid_loss_year?(year)
    d = get_financial_data_by_year(year)
    (d[:roe].present? && d[:roe].to_f <= 0) || (d[:net_income].present? && d[:net_income].to_f < 0)
  end
end
