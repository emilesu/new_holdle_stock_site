# 金字塔评分排行：板块 / 行业筛选与完整榜单为会员专属，非会员仅展示示例（A股公用事业 Top 5，分数与标签打码）
class PyramidsController < ApplicationController
  PER_PAGE = 20
  # 非会员示例条件：固定 A股「公用事业」板块，仅取 Top 5（真实股票，分数/标签在前端渲染为掩码）
  DEMO_MARKET = 'CN'
  DEMO_SECTOR = '公用事业'
  DEMO_LIMIT = 5

  # 非会员不允许执行真实筛选：绕过前端遮罩直接请求筛选 / 分页接口时一律拒绝
  before_action :require_member_access, only: %i[update_sectors update_industries update_list load_more]

  def index
    @is_member = member_access?
    @can_select_sector = @is_member

    if @is_member
      @market = params[:market] || 'CN'
      @sector = params[:sector] || ''
      @industry = @sector.present? ? (params[:industry].presence || '') : ''
      @page = params[:page] ? params[:page].to_i : 1
    else
      # 非会员固定示例条件，忽略 URL 参数，避免绕过会员墙拿到真实筛选结果
      @market = DEMO_MARKET
      @sector = DEMO_SECTOR
      @industry = ''
      @page = 1
    end

    stocks = Stock.where(market: @market)
    stocks = stocks.where(sector: @sector) if @sector.present? && @sector != 'all'
    stocks = stocks.where(industry: @industry) if @industry.present?
    
    @total_count = stocks.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @stocks = if @is_member
      stocks.order(pyramid_total_score: :desc, id: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    else
      stocks.order(pyramid_total_score: :desc, id: :desc).limit(DEMO_LIMIT)
    end
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
    @industries = @sector.present? ? industries_for(@market, @sector) : []

    respond_to do |format|
      format.turbo_stream
    end
  end

  def update_list
    @market = params[:market] || 'CN'
    @sector = params[:sector] || ''
    @industry = @sector.present? ? (params[:industry].presence || '') : ''
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
    @sector = params[:sector] || ''
    @industry = @sector.present? ? (params[:industry].presence || '') : ''
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

  # 会员（含管理员）才有板块 / 行业筛选与完整榜单权限
  def member_access?
    user_signed_in? && current_user.is_member?
  end

  # 非会员不允许执行真实筛选：绕过前端遮罩直接调筛选 / 分页接口时返回 403
  def require_member_access
    head :forbidden unless member_access?
  end

  # 获取某市场某板块下的行业列表（带缓存）
  def industries_for(market, sector)
    Rails.cache.fetch("pyramid_industries_#{market}_#{sector}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: market, sector: sector).where.not(industry: nil).distinct.pluck(:industry).sort
    end
  end
end
