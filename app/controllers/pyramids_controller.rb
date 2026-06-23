class PyramidsController < ApplicationController
  before_action :authenticate_user!

  PER_PAGE = 20

  def index
    @market = params[:market] || 'CN'
    @sector = params[:sector]
    @page = params[:page] ? params[:page].to_i : 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @top_stock = @stocks.first

    @sectors = Rails.cache.fetch("pyramid_sectors_#{@market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: @market).where.not(sector: nil).distinct.pluck(:sector).sort
    end

    @compare_data = if @top_stock
      DataSources::StockRadarCompareService.call(@top_stock)
    else
      nil
    end
  end

  def compare
    base_stock = Stock.find_by(id: params[:base_id])
    compare_stock = params[:compare_id].present? ? Stock.find_by(id: params[:compare_id]) : nil

    unless base_stock
      render json: { success: false, error: '基准股票不存在' }, status: :not_found
      return
    end

    result = DataSources::StockRadarCompareService.call(base_stock, compare_stock)
    render json: { success: true, data: result }
  end

  def update_sectors
    @market = params[:market] || 'CN'
    
    @sectors = Rails.cache.fetch("pyramid_sectors_#{@market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: @market).where.not(sector: nil).distinct.pluck(:sector).sort
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def update_list
    @market = params[:market] || 'CN'
    @sector = params[:sector]
    @page = 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @top_stock = @stocks.first

    @compare_data = if @top_stock
      DataSources::StockRadarCompareService.call(@top_stock)
    else
      nil
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def load_more
    @market = params[:market] || 'CN'
    @sector = params[:sector]
    @page = (params[:page] || 2).to_i
    @base_page = 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def authenticate_user!
    unless user_signed_in?
      redirect_to new_user_session_path, alert: '请先登录'
    end
  end
end