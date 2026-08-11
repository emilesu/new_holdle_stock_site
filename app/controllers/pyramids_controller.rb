class PyramidsController < ApplicationController
  PER_PAGE = 20

  def index
    @market = params[:market] || 'CN'
    @can_select_sector = user_signed_in? && current_user.is_member?
    @sector = @can_select_sector ? (params[:sector] || '') : '公用事业'
    @industry = (@can_select_sector && @sector.present?) ? (params[:industry].presence || '') : ''
    @page = params[:page] ? params[:page].to_i : 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    stocks = stocks.where(industry: @industry) if @industry.present?
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    Stock.preload_pyramid_financials(@stocks)
    @tags = Stock.pyramid_tags_for(@stocks)
    @top_stock = @stocks.first

    @sectors = Rails.cache.fetch("pyramid_sectors_#{@market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: @market).where.not(sector: nil).distinct.pluck(:sector).sort
    end

    @industries = (@can_select_sector && @sector.present?) ? industries_for(@market, @sector) : []

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
    @can_select_sector = user_signed_in? && current_user.is_member?
    
    @sectors = Rails.cache.fetch("pyramid_sectors_#{@market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: @market).where.not(sector: nil).distinct.pluck(:sector).sort
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def update_industries
    @market = params[:market] || 'CN'
    @sector = params[:sector]
    @can_select_sector = user_signed_in? && current_user.is_member?
    @industries = (@can_select_sector && @sector.present?) ? industries_for(@market, @sector) : []

    respond_to do |format|
      format.turbo_stream
    end
  end

  def update_list
    @market = params[:market] || 'CN'
    @can_select_sector = user_signed_in? && current_user.is_member?
    @sector = @can_select_sector ? (params[:sector] || '') : '公用事业'
    @industry = (@can_select_sector && @sector.present?) ? (params[:industry].presence || '') : ''
    @page = 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    stocks = stocks.where(industry: @industry) if @industry.present?
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    Stock.preload_pyramid_financials(@stocks)
    @tags = Stock.pyramid_tags_for(@stocks)
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

  def permission
    render json: { can_select_sector: user_signed_in? && current_user.is_member? }
  end

  def load_more
    @market = params[:market] || 'CN'
    @can_select_sector = user_signed_in? && current_user.is_member?
    @sector = @can_select_sector ? (params[:sector] || '') : '公用事业'
    @industry = (@can_select_sector && @sector.present?) ? (params[:industry].presence || '') : ''
    @page = (params[:page] || 2).to_i
    @base_page = 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    stocks = stocks.where(industry: @industry) if @industry.present?
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    Stock.preload_pyramid_financials(@stocks)
    @tags = Stock.pyramid_tags_for(@stocks)

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  # 获取某市场某板块下的行业列表（带缓存）
  def industries_for(market, sector)
    Rails.cache.fetch("pyramid_industries_#{market}_#{sector}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: market, sector: sector).where.not(industry: nil).distinct.pluck(:industry).sort
    end
  end
end
