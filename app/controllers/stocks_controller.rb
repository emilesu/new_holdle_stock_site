class StocksController < ApplicationController
  before_action :set_stock, only: [:show]

  def autocomplete
    query = params[:q].to_s.strip
    
    if query.length < 1
      render json: []
      return
    end

    stocks = Stock.where("symbol ILIKE ? OR name ILIKE ?", "%#{query}%", "%#{query}%")
      .limit(10)
      .select(:id, :symbol, :name, :market, :exchange)

    results = stocks.map do |stock|
      market_label = stock.market == 'CN' ? 'A股' : '美股'
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
    @financial_indicators = @stock.financial_indicators.order(report_date: :desc).limit(8)
    @income_statements = @stock.income_statements.order(report_date: :desc).limit(8)
    @cash_flows = @stock.cash_flows.order(report_date: :desc).limit(8)
    @balance_sheets = @stock.balance_sheets.order(report_date: :desc).limit(8)
    
    @industry_comparison = Stock.where.not(id: @stock.id)
      .where(sector: @stock.sector)
      .order(:id)
      .limit(10)
    
    latest_indicator = @financial_indicators.first
    @radar_data = {
      labels: ['ROE', 'ROA', '毛利率', '净利率', 'EPS', '现金流'],
      datasets: [{
        label: @stock.symbol,
        data: [
          latest_indicator&.roe_avg.present? ? latest_indicator.roe_avg : 0,
          latest_indicator&.net_interest_of_ta.present? ? latest_indicator.net_interest_of_ta : 0,
          latest_indicator&.gross_margin.present? ? latest_indicator.gross_margin : 0,
          latest_indicator&.operating_margin.present? ? latest_indicator.operating_margin : 0,
          latest_indicator&.basic_eps.present? ? latest_indicator.basic_eps : 0,
          latest_indicator&.ncf_from_oa_ps.present? ? latest_indicator.ncf_from_oa_ps : 0
        ],
        backgroundColor: 'rgba(59, 130, 246, 0.2)',
        borderColor: 'rgb(59, 130, 246)',
        borderWidth: 2,
        pointBackgroundColor: 'rgb(59, 130, 246)',
        pointBorderColor: '#fff',
        pointBorderWidth: 2
      }]
    }
  end

  private

  def set_stock
    param = params[:id]
    
    if param.include?('-')
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