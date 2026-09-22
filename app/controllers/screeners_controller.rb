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

    @latest_year = Date.current.year - 1
    @default_year_from = @latest_year - 4

    @screened = @is_member && params[:screen].present?
    if @screened
      @result = StockScreenerService.call(params)
      @conditions = @result.conditions
    elsif !@is_member
      @demo = cached_demo_result
    end
  end

  private

  # 板块列表与金字塔页共用同一缓存键，避免重复计算
  def cached_sectors(market)
    Rails.cache.fetch("pyramid_sectors_#{market}_#{Date.current}", expires_in: 1.hour) do
      Stock.where(market: market).where.not(sector: nil).distinct.pluck(:sector).sort
    end
  end

  # 非会员示例：仅缓存 stock_id 列表，渲染时按 id 取最新名称/代码（指标列展示为掩码，无需缓存指标）
  def cached_demo_result
    ids = Rails.cache.fetch("screener_demo_#{Date.current}", expires_in: 1.day) do
      result = StockScreenerService.call(DEMO_PARAMS)
      result.ok? ? result.stocks.first(DEMO_LIMIT).map(&:id) : []
    end
    Stock.where(id: ids).in_order_of(:id, ids)
  end
end
