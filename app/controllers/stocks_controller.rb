class StocksController < ApplicationController
  HUNDRED_MILLION = 100_000_000
  MAX_QUERY_LENGTH = 100
  AUTOCOMPLETE_LIMIT = 10
  INDUSTRY_COMPARISON_LIMIT = 20
  CACHE_EXPIRES_IN = 6.hours
  INDUSTRY_CACHE_EXPIRES_IN = 12.hours
  
  before_action :set_stock, only: [:show]

  def autocomplete
    query = params[:q].to_s.squish
    
    if query.length < 1 || query.length > MAX_QUERY_LENGTH
      render json: []
      return
    end

    stocks = Stock.where("symbol ILIKE :q OR name ILIKE :q", q: "%#{query}%")
      .limit(AUTOCOMPLETE_LIMIT)
      .select(:id, :symbol, :name, :market, :exchange)

    results = stocks.map do |stock|
      market_label = stock.market == 'CN' ? 'A股' : stock.market == 'HK' ? '港股' : '美股'
      {
        id: stock.id,
        symbol: stock.symbol,
        name: stock.name,
        market: stock.market,
        market_label: market_label,
        url: stock_path(stock)
      }
    end

    render json: results
  end

  def show
    @financial_data_by_year = @stock.cached_financial_data
    @financial_years = @financial_data_by_year.keys.sort
    
    @industry_comparison_data = Rails.cache.fetch(
      [:industry_comparison, @stock.sector, Date.current].join('/'),
      expires_in: INDUSTRY_CACHE_EXPIRES_IN
    ) do
      sector_stocks = Stock.where(sector: @stock.sector).includes(
        financial_reports: [:financial_indicators, :income_statements, :balance_sheets, :cash_flows]
      ).to_a
      
      sector_stocks.each do |stock|
        stock.preloaded_income_statements = stock.income_statements.to_a
        stock.preloaded_balance_sheets = stock.balance_sheets.to_a
        stock.preloaded_cash_flows = stock.cash_flows.to_a
        stock.preloaded_financial_indicators = stock.financial_indicators.to_a
      end
      
      sector_stocks.map do |stock|
        {
          stock: stock,
          roe_average: stock.cached_five_year_roe,
          is_current_stock: stock.id == @stock.id
        }
      end.select { |item| item[:roe_average].present? }
         .sort_by { |item| -item[:roe_average] }
         .first(INDUSTRY_COMPARISON_LIMIT)
    end

    @radar_data = build_radar_data(@stock)
    @comparison_radar_data = build_comparison_radar_data

    @user_favorite = current_user&.user_favorites&.find_by(stock_id: @stock.id)

    preformat_financial_data
  end

  def indicator_detail
    stock = Stock.find_by(symbol: params[:id])
    indicator_key = params[:indicator_key].presence
    
    unless stock
      render json: { success: false, error: "股票不存在" }, status: :not_found
      return
    end
    
    unless indicator_key.present?
      render json: { success: false, error: "指标类型不能为空" }, status: :bad_request
      return
    end
    
    unless valid_indicator?(indicator_key)
      render json: { success: false, error: "无效的指标类型: #{indicator_key}" }, status: :bad_request
      return
    end
    
    data = Rails.cache.fetch(
      [stock, :indicator_detail, indicator_key, stock.updated_at.to_i],
      expires_in: 6.hours
    ) do
      fetch_indicator_detail(stock, indicator_key)
    end
    
    render json: { success: true, data: data }
  end

  private

  def valid_indicators
    [
      :roe, :roa, :gross_margin, :net_profit_margin, :eps, :cash_flow_ps,
      :asset_liab_ratio, :asset_turnover_ratio, :net_income, 
      :operating_cash_flow, :investing_cash_flow, :financing_cash_flow,
      :net_cash_change
    ]
  end

  def valid_indicator?(key)
    valid_indicators.include?(key.to_sym)
  end

  def fetch_indicator_detail(stock, indicator_key)
    years = stock.financial_years.last(8)
    data_points = years.map do |year|
      data = stock.get_financial_data_by_year(year)
      value = data[indicator_key.to_sym]
      {
        year: year,
        value: value,
        formatted: format_value(value, indicator_key)
      }
    end

    info = get_indicator_info(indicator_key)

    {
      stock_symbol: stock.symbol,
      stock_name: stock.name,
      indicator_key: indicator_key,
      indicator_name: info[:name],
      data_points: data_points,
      description: info[:description],
      formula: info[:formula],
      interpretation: info[:interpretation],
      unit: info[:unit]
    }
  end

  def get_indicator_info(indicator_key)
    key = indicator_key.to_sym
    {
      roe: {
        name: 'ROE(净资产收益率)',
        description: 'ROE即净资产收益率，是衡量公司运用自有资本效率的核心财务指标。它反映了股东权益的收益水平，指标值越高，说明投资带来的收益越高。ROE是评估上市公司盈利能力的关键指标。',
        formula: 'ROE = 归属于母公司所有者的净利润 / 平均股东权益 × 100%',
        unit: '%',
        interpretation: {
          excellent: 'ROE > 20%：具备极佳的投资价值，公司盈利能力非常出色',
          good: '15% ≤ ROE ≤ 20%：盈利能力优秀，值得关注',
          normal: '10% ≤ ROE < 15%：盈利能力一般，需要综合评估',
          poor: 'ROE < 10%：盈利能力较弱，投资需谨慎'
        }
      },
      roa: {
        name: 'ROA(总资产收益率)',
        description: 'ROA即总资产收益率，反映公司运用全部资产获取利润的能力。它衡量了企业资产的利用效率，是评估企业运营效率的重要指标。',
        formula: 'ROA = 净利润 / 平均总资产 × 100%',
        unit: '%',
        interpretation: {
          excellent: 'ROA > 15%：资产利用效率非常高',
          good: '10% ≤ ROA ≤ 15%：资产利用效率良好',
          normal: '5% ≤ ROA < 10%：资产利用效率一般',
          poor: 'ROA < 5%：资产利用效率较低'
        }
      },
      gross_margin: {
        name: '毛利率',
        description: '毛利率是毛利与营业收入的比率，反映了公司产品或服务的定价能力和成本控制水平。毛利率越高，说明公司在产业链中拥有更强的议价能力。',
        formula: '毛利率 = (营业收入 - 营业成本) / 营业收入 × 100%',
        unit: '%',
        interpretation: {
          excellent: '毛利率 > 60%：具备很强的定价权',
          good: '40% ≤ 毛利率 ≤ 60%：定价能力良好',
          normal: '20% ≤ 毛利率 < 40%：处于行业平均水平',
          poor: '毛利率 < 20%：毛利率较低'
        }
      },
      net_profit_margin: {
        name: '净利率',
        description: '净利率是净利润与营业收入的比率，反映了公司最终的盈利能力。它考虑了所有成本、费用和税收因素。',
        formula: '净利率 = 归属于母公司所有者的净利润 / 营业收入 × 100%',
        unit: '%',
        interpretation: {
          excellent: '净利率 > 25%：盈利能力非常强',
          good: '15% ≤ 净利率 ≤ 25%：盈利能力优秀',
          normal: '5% ≤ 净利率 < 15%：处于行业平均水平',
          poor: '净利率 < 5%：净利润率较低'
        }
      },
      eps: {
        name: 'EPS(每股收益)',
        description: 'EPS即每股收益，是衡量普通股股东每持有一股所能享有的企业净利润。它是投资者评估股票价值的重要指标之一。',
        formula: 'EPS = 归属于母公司所有者的净利润 / 加权平均在外普通股股数',
        unit: '',
        interpretation: {
          excellent: 'EPS持续增长且高于行业平均，分红潜力大',
          good: 'EPS稳定且为正，公司盈利稳健',
          normal: 'EPS波动但整体为正，需关注盈利稳定性',
          poor: 'EPS为负或持续下降，需谨慎评估'
        }
      },
      cash_flow_ps: {
        name: '每股现金流量',
        description: '每股现金流量是经营活动产生的现金流量净额除以加权平均在外普通股股数。它反映了公司每股股票所能获得的现金流量，是评估盈利质量的重要指标。',
        formula: '每股现金流量 = 经营活动现金流量净额 / 加权平均在外普通股股数',
        unit: '',
        interpretation: {
          excellent: '每股现金流量持续为正且高于EPS',
          good: '每股现金流量为正且与EPS相当',
          normal: '每股现金流量波动但整体为正',
          poor: '每股现金流量为负或持续低于EPS'
        }
      },
      asset_liab_ratio: {
        name: '负债占资产比率',
        description: '资产负债率是企业负债总额与资产总额的比率，反映了企业的财务杠杆水平和偿债能力。适度的负债可以提升ROE，但过高的负债会增加财务风险。',
        formula: '资产负债率 = 总负债 / 总资产 × 100%',
        unit: '%',
        interpretation: {
          excellent: '资产负债率 < 40%：财务结构稳健',
          good: '40% ≤ 资产负债率 ≤ 60%：财务杠杆适中',
          normal: '60% ≤ 资产负债率 < 80%：财务杠杆较高',
          poor: '资产负债率 ≥ 80%：财务风险较高'
        }
      },
      asset_turnover_ratio: {
        name: '总资产周转率',
        description: '总资产周转率是营业收入与平均总资产的比率，反映了公司资产运营效率。周转率越高，说明公司资产运营效率越高。',
        formula: '总资产周转率 = 营业收入 / 平均总资产',
        unit: '%',
        interpretation: {
          excellent: '总资产周转率 > 150%：资产运营效率很高',
          good: '100% ≤ 总资产周转率 ≤ 150%：资产运营效率良好',
          normal: '50% ≤ 总资产周转率 < 100%：资产运营效率一般',
          poor: '总资产周转率 < 50%：资产运营效率较低'
        }
      },
      net_income: {
        name: '净利润',
        description: '净利润是企业在一定会计期间的经营成果，是扣除所有成本、费用和税费后的剩余利润。它是衡量企业盈利能力的核心指标。',
        formula: '净利润 = 营业收入 - 营业成本 - 期间费用 - 所得税费用',
        unit: '亿元',
        interpretation: {
          excellent: '净利润持续增长，增长率高于行业平均',
          good: '净利润稳定，波动较小',
          normal: '净利润有波动但整体呈上升趋势',
          poor: '净利润持续下降或为负'
        }
      },
      operating_cash_flow: {
        name: '经营活动现金流量',
        description: '经营活动现金流量是企业在日常经营活动中产生的现金流入与流出的净额。它反映了企业主营业务产生现金的能力，是评估企业财务健康状况的关键指标。',
        formula: '经营活动现金流量 = 销售商品提供劳务收到的现金 - 购买商品接受劳务支付的现金 - 支付给职工以及为职工支付的现金 - 支付的各项税费',
        unit: '亿元',
        interpretation: {
          excellent: '经营活动现金流量持续为正且与净利润匹配',
          good: '经营活动现金流量为正，基本与净利润相当',
          normal: '经营活动现金流量有波动但整体为正',
          poor: '经营活动现金流量为负或与净利润差距较大'
        }
      },
      investing_cash_flow: {
        name: '投资活动现金流量',
        description: '投资活动现金流量是企业在投资活动中产生的现金流入与流出的净额。包括购建固定资产、无形资产和其他长期资产所支付的现金，以及处置这些资产所收到的现金。',
        formula: '投资活动现金流量 = 收回投资收到的现金 + 取得投资收益收到的现金 - 购建固定资产等支付的现金 - 投资支付的现金',
        unit: '亿元',
        interpretation: {
          excellent: '投资活动现金流量为正，说明公司正在回收投资',
          good: '投资活动现金流量为负但投资方向明确',
          normal: '投资活动现金流量有一定波动',
          poor: '投资活动现金流量大幅波动且方向不明'
        }
      },
      financing_cash_flow: {
        name: '筹资活动现金流量',
        description: '筹资活动现金流量是企业在筹资活动中产生的现金流入与流出的净额。包括吸收投资、发行股票、借款所收到的现金，以及偿还债务、支付股利所支付的现金。',
        formula: '筹资活动现金流量 = 吸收投资收到的现金 + 取得借款收到的现金 - 偿还债务支付的现金 - 分配股利利润支付的现金',
        unit: '亿元',
        interpretation: {
          excellent: '筹资活动现金流量为负，说明公司正在偿还债务或分红',
          good: '筹资活动现金流量与公司发展阶段匹配',
          normal: '筹资活动现金流量有一定波动',
          poor: '筹资活动现金流量大幅依赖外部融资'
        }
      },
      net_cash_change: {
        name: '净现金流量',
        description: '净现金流量是指一定时期内，现金及现金等价物的流入减去流出的余额。它是衡量企业现金状况变化的重要指标，反映了企业在一定时期内的现金净增加或净减少。',
        formula: '净现金流量 = 经营活动现金流量 + 投资活动现金流量 + 筹资活动现金流量',
        unit: '亿元',
        interpretation: {
          excellent: '净现金流量持续为正，现金储备充足',
          good: '净现金流量基本稳定',
          normal: '净现金流量有波动但整体可控',
          poor: '净现金流量持续为负，需关注现金状况'
        }
      }
    }[key] || { name: indicator_key.humanize, description: '暂无说明', formula: '暂无公式', unit: '%', interpretation: {} }
  end

  def format_value(value, indicator_key)
    return '-' unless value.present?
    value = value.to_f if value.is_a?(String)
    
    case indicator_key.to_sym
    when :eps, :cash_flow_ps
      "%.2f" % value
    when :net_income, :operating_cash_flow, :investing_cash_flow, :financing_cash_flow, :net_cash_change
      "%.2f" % (value / HUNDRED_MILLION)
    else
      # 所有百分比指标（包括ROE, ROA, gross_margin, net_profit_margin等）
      # 已经在 Stock 模型的 calculate_* 方法中处理为正确的百分比值
      "%.2f%%" % value
    end
  end

  def build_radar_data(stock)
    values = stock.radar_dim_scores.presence || {}
    {
      values: values,
      name: stock.name,
      display_name: stock.display_name_for_comparison
    }
  end

  def build_comparison_radar_data
    return {} unless @industry_comparison_data

    @industry_comparison_data.each_with_object({}) do |item, hash|
      stock = item[:stock]
      values = stock.radar_dim_scores.presence || {}
      hash[stock.symbol] = {
        values: values,
        name: stock.name,
        display_name: stock.display_name_for_comparison
      }
    end
  end

  def preformat_financial_data
    @formatted_financial_data = @financial_data_by_year.transform_values do |data|
      {
        roe: data[:roe].present? ? "%.2f%%" % data[:roe] : '-',
        gross_margin: data[:gross_margin].present? ? "%.2f%%" % data[:gross_margin] : '-',
        net_profit_margin: data[:net_profit_margin].present? ? "%.2f%%" % data[:net_profit_margin] : '-',
        eps: data[:eps].present? ? "%.2f" % data[:eps] : '-',
        asset_liab_ratio: data[:asset_liab_ratio].present? ? "%.2f%%" % data[:asset_liab_ratio] : '-',
        asset_turnover_ratio: data[:asset_turnover_ratio].present? ? "%.2f" % data[:asset_turnover_ratio] : '-',
        operating_margin: data[:operating_margin].present? ? "%.2f%%" % data[:operating_margin] : '-'
      }
    end
  end

  def set_stock
    param = params[:id]
    
    if param.match?(/\AHK\d+\z/)
      symbol = "#{param.sub(/\AHK/, '')}.HK"
      @stock = Stock.find_by(symbol: symbol, market: 'HK')
    elsif param.include?('-')
      parts = param.split('-', 2)
      exchange = parts[0]
      symbol = parts[1]
      @stock = Stock.find_by(exchange: exchange, symbol: symbol) || Stock.find_by(symbol: symbol)
    else
      @stock = Stock.find_by(symbol: param)
    end
    
    unless @stock
      raise ActiveRecord::RecordNotFound
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: '股票不存在或尚未收录'
  end
end