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
    @financial_years = @stock.financial_years
    
    @financial_data_by_year = {}
    @financial_years.each do |year|
      @financial_data_by_year[year] = @stock.get_financial_data_by_year(year)
    end
    
    @industry_comparison = Stock.where.not(id: @stock.id)
      .where(sector: @stock.sector)
      .order(:id)
      .limit(10)
    
    latest_data = @financial_data_by_year[@financial_years.last]
    @radar_data = {
      labels: ['ROE', 'ROA', '毛利率', '净利率', 'EPS', '现金流'],
      datasets: [{
        label: @stock.symbol,
        data: [
          latest_data&.dig(:roe) || 0,
          latest_data&.dig(:roa) || 0,
          latest_data&.dig(:gross_margin) || 0,
          latest_data&.dig(:net_profit_margin) || 0,
          latest_data&.dig(:eps) || 0,
          latest_data&.dig(:cash_flow_ps) || 0
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