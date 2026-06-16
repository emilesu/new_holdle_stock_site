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
    
    sector_stocks = Stock.where(sector: @stock.sector).to_a
    @industry_comparison_data = sector_stocks.map do |stock|
      roe_avg = stock.five_year_roe_average
      {
        stock: stock,
        roe_average: roe_avg,
        is_current_stock: stock.id == @stock.id
      }
    end.select { |item| item[:roe_average].present? }
       .sort_by { |item| -item[:roe_average] }
       .first(20)

    @radar_data = StockRadarDataService.call(@stock)
    @comparison_radar_data = if @industry_comparison_data.present?
      StockRadarDataService.batch_call(@industry_comparison_data.map { |item| item[:stock] })
    else
      {}
    end
  end

  def radar_comparison
    stock = Stock.find_by(symbol: params[:id])
    unless stock
      Rails.logger.warn "雷达图对比API：股票不存在 - #{params[:id]}"
      render json: { error: '股票不存在' }, status: :not_found
      return
    end

    data = StockRadarDataService.call(stock)
    if data
      Rails.logger.info "雷达图对比API：成功获取 #{stock.symbol} 的数据"
      render json: data
    else
      Rails.logger.warn "雷达图对比API：股票无财务数据 - #{stock.symbol}"
      render json: { error: '该股票暂无财务数据' }, status: :not_found
    end
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