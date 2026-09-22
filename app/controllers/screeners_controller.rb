# 股票筛选（Screener）：会员专属，按财务指标 + 年度区间组合筛选股票
class ScreenersController < ApplicationController
  # 非会员示例查询：近 5 个完整财年每年 ROE≥20%（按日缓存，仅取前 5 行展示）
  DEMO_PARAMS = { market: 'CN', margin_mode: 'all', roe_value: '20' }.freeze
  DEMO_LIMIT = 5

  def index
    @is_member = user_signed_in? && current_user.is_member?
    @market = params[:market].to_s.presence || 'CN'
    @market = 'CN' unless StockScreenerService::MARKETS.include?(@market)

    @sectors = cached_sectors(@market)
    @sector = params[:sector].to_s.strip
    @sector = nil if @sector.empty? || @sector == 'all'
    @industry = params[:industry].to_s.strip
    @industry = nil if @industry.empty? || @industry == 'all'
    @industries = @sector ? industries_for(@market, @sector) : []

    @latest_year = Date.current.year - 1
    @default_year_from = @latest_year - 4

    @favorite_stock_ids = []
    # 非会员示例的服务端条件：用于让示例表与会员真实结果表结构一致（会员路径下为空）
    @demo_conditions = {}
    @screened = @is_member && params[:screen].present?
    if @screened
      @result = StockScreenerService.call(params)
      @conditions = @result.conditions
      @favorite_stock_ids = favorite_stock_ids(@result.stocks)
    elsif !@is_member
      @demo = cached_demo_result
    end
  end

  # 筛选项 JSON：按市场返回板块列表，按市场+板块返回行业列表（前端级联刷新用）
  def filters
    market = params[:market].to_s
    market = 'CN' unless StockScreenerService::MARKETS.include?(market)
    sector = params[:sector].to_s.strip
    sector = nil if sector.empty? || sector == 'all'
    render json: { sectors: cached_sectors(market), industries: sector ? industries_for(market, sector) : [] }
  end

  private

  # 板块列表与金字塔页共用同一缓存键，避免重复计算
  def cached_sectors(market)
    Rails.cache.fetch("pyramid_sectors_#{market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: market).where.not(sector: nil).distinct.pluck(:sector).sort
    end
  end

  # 行业列表与金字塔页共用同一缓存键
  def industries_for(market, sector)
    Rails.cache.fetch("pyramid_industries_#{market}_#{sector}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: market, sector: sector).where.not(industry: nil).distinct.pluck(:industry).sort
    end
  end

  # 当前用户在本页结果中的已收藏股票 id 集合（单次查询，供结果列表显示「已收藏」小图标）
  def favorite_stock_ids(stocks)
    return [] unless user_signed_in?

    ids = stocks.map(&:id)
    return [] if ids.empty?

    current_user.user_favorites.where(stock_id: ids).pluck(:stock_id)
  end

  # 非会员示例：缓存 stock_id 列表与服务端解析后的示例条件
  # 条件用于让示例表与会员真实结果表同构（同样的年份列与指标行），指标数值仍按 id 取最新数据但渲染为掩码，无需缓存
  # 键名带 v2：旧版缓存值是纯数组，结构变更后换键避免类型冲突
  def cached_demo_result
    cached = Rails.cache.fetch("screener_demo_v2_#{Date.current}", expires_in: 1.day) do
      result = StockScreenerService.call(DEMO_PARAMS)
      if result.ok?
        { ids: result.stocks.first(DEMO_LIMIT).map(&:id), conditions: result.conditions }
      else
        { ids: [], conditions: {} }
      end
    end
    @demo_conditions = cached[:conditions] || {}
    Stock.where(id: cached[:ids]).in_order_of(:id, cached[:ids])
  end
end
