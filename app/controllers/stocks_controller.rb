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
    @financial_data_by_year = @stock.cached_financial_data
    @financial_years = @financial_data_by_year.keys.sort
    
    @industry_comparison_data = Rails.cache.fetch(
      [:industry_comparison, @stock.sector, Date.today].join('/'),
      expires_in: 12.hours
    ) do
      sector_stocks = Stock.where(sector: @stock.sector).includes(
        financial_reports: [:financial_indicators, :income_statements, :balance_sheets]
      ).to_a
      
      sector_stocks.map do |stock|
        {
          stock: stock,
          roe_average: stock.cached_five_year_roe,
          is_current_stock: stock.id == @stock.id
        }
      end.select { |item| item[:roe_average].present? }
         .sort_by { |item| -item[:roe_average] }
         .first(20)
    end

    @radar_data = @stock.cached_radar_data
    @comparison_radar_data = fetch_comparison_radar_data

    preformat_financial_data
  end

  private

  def fetch_comparison_radar_data
    stocks = @industry_comparison_data.map { |item| item[:stock] }
    result = {}
    stocks.each do |stock|
      data = stock.cached_radar_data
      result[stock.symbol] = data if data
    end
    result
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