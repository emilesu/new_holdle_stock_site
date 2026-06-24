module Admin
  class StocksController < BaseController
    before_action :set_stock, only: [:recalculate_pyramid]

    PER_PAGE = 20

    def index
      @market = params[:market] || 'CN'
      @sector = params[:sector]
      @pyramid_min = params[:pyramid_min]
      @pyramid_max = params[:pyramid_max]
      @page = params[:page] ? params[:page].to_i : 1

      stocks = Stock.where(market: @market)
      stocks = stocks.where(sector: @sector) if @sector.present?
      stocks = stocks.where('pyramid_total_score >= ?', @pyramid_min) if @pyramid_min.present?
      stocks = stocks.where('pyramid_total_score <= ?', @pyramid_max) if @pyramid_max.present?

      @total_count = stocks.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @stocks = stocks.order(pyramid_total_score: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      
      @sectors = Rails.cache.fetch("sectors_#{@market}_#{Date.current}", expires_in: 1.hour) do
        Stock.where(market: @market).where.not(sector: nil).distinct.pluck(:sector).sort
      end
    end

    def recalculate_pyramid
      result = DataSources::StockPyramidService.call(@stock)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "stock-#{@stock.id}",
              partial: 'admin/stocks/stock_row',
              locals: { stock: @stock.reload }
            )
          ]
        end
        format.html do
          redirect_to admin_stocks_path, notice: result[:success] ? '计算成功' : "计算失败: #{result[:error]}"
        end
      end
    rescue => e
      Rails.logger.error "Recalculate pyramid error for #{@stock&.symbol}: #{e.message}"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "stock-#{@stock&.id}",
              partial: 'admin/stocks/stock_row',
              locals: { stock: @stock&.reload }
            )
          ]
        end
        format.html do
          redirect_to admin_stocks_path, alert: "计算失败: #{e.message}"
        end
      end
    end

    def sectors
      market = params[:market] || 'CN'
      sectors = Stock.where(market: market).where.not(sector: nil).distinct.pluck(:sector).sort
      render json: sectors
    end

    private

    def set_stock
      @stock = Stock.find(params[:id])
    end
  end
end