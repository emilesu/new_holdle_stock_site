class PyramidsController < ApplicationController
  PER_PAGE = 20

  def index
    @market = params[:market] || 'CN'
    @can_select_sector = user_signed_in? && current_user.is_member?
    @sector = @can_select_sector ? (params[:sector] || '') : '公用事业'
    @page = params[:page] ? params[:page].to_i : 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    preload_pyramid_financials(@stocks)
    @tags = Stock.pyramid_tags_for(@stocks)
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
    @can_select_sector = user_signed_in? && current_user.is_member?
    
    @sectors = Rails.cache.fetch("pyramid_sectors_#{@market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: @market).where.not(sector: nil).distinct.pluck(:sector).sort
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def update_list
    @market = params[:market] || 'CN'
    @can_select_sector = user_signed_in? && current_user.is_member?
    @sector = @can_select_sector ? (params[:sector] || '') : '公用事业'
    @page = 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    preload_pyramid_financials(@stocks)
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
    @sector = params[:sector]
    @page = (params[:page] || 2).to_i
    @base_page = 1

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    preload_pyramid_financials(@stocks)
    @tags = Stock.pyramid_tags_for(@stocks)

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  # 预加载金字塔列表所需财务数据到模型 accessor，批量计算警示标签避免 N+1
  def preload_pyramid_financials(stocks)
    ids = stocks.map(&:id)
    return if ids.empty?

    reports = FinancialReport.where(stock_id: ids).includes(:financial_indicators, :income_statements).group_by(&:stock_id)
    stocks.each do |s|
      rs = reports[s.id] || []
      # 无财务数据的股票用 [nil] 哨兵，确保 financial_years 走内存分支而非触发查询
      s.preloaded_income_statements = rs.empty? ? [nil] : rs.flat_map { |r| r.income_statements.to_a }
      s.preloaded_financial_indicators = rs.empty? ? [nil] : rs.flat_map { |r| r.financial_indicators.to_a }
    end
  end

end