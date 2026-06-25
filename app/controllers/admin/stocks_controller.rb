module Admin
  class StocksController < BaseController
    before_action :set_stock, only: [:show, :recalculate_pyramid]

    PER_PAGE = 20

    def show
      @income_statements = IncomeStatement
        .where(stock_id: @stock.id, market: @stock.market)
        .where("report_date >= ?", 10.years.ago)
        .order(report_date: :desc)
      @balance_sheets = BalanceSheet
        .where(stock_id: @stock.id, market: @stock.market)
        .where("report_date >= ?", 10.years.ago)
        .order(report_date: :desc)
      @cash_flows = CashFlow
        .where(stock_id: @stock.id, market: @stock.market)
        .where("report_date >= ?", 10.years.ago)
        .order(report_date: :desc)
      @financial_indicators = FinancialIndicator
        .where(stock_id: @stock.id, market: @stock.market)
        .where("report_date >= ?", 10.years.ago)
        .order(report_date: :desc)

      # 确定年报日期：
      # 优先使用 financial_indicators 的日期（爬虫已精确过滤为年报）
      # 若没有，则从四张表的并集中推断（取出现频率最高的 month-day 作为年报日期）
      indicator_dates = @financial_indicators.pluck(:report_date)
      if indicator_dates.any?
        @annual_dates = indicator_dates.sort.reverse.first(10)
      else
        all_dates = (@income_statements.pluck(:report_date) |
                     @balance_sheets.pluck(:report_date) |
                     @cash_flows.pluck(:report_date) |
                     @financial_indicators.pluck(:report_date)).sort.reverse
        # 统计各 month-day 组合的出现频率，取最高频的作为年报日期
        freq = all_dates.group_by { |d| [d.month, d.day] }.transform_values(&:size)
        top_md = freq.max_by { |_, v| v }&.first || [12, 31]
        @annual_dates = all_dates
          .select { |d| d.month == top_md[0] && d.day == top_md[1] }
          .first(10)
      end
    end

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
      param = params[:id]

      @stock = if param.match?(/\AHK\d+\z/)
        # 港股格式: HK09988 → 09988.HK
        symbol = "#{param.sub(/\AHK/, '')}.HK"
        Stock.find_by(symbol: symbol, market: 'HK')
      elsif param.match?(/\A[AS]H\d+\z/)
        # A股格式: SH600519 / SZ000858
        Stock.find_by(symbol: param)
      elsif param.include?('-')
        # 美股格式: NASDAQ-AAPL
        parts = param.split('-', 2)
        exchange = parts[0].gsub('证券交易所', '').strip.upcase
        symbol = parts[1]
        Stock.find_by(exchange: exchange, symbol: symbol) || Stock.find_by(symbol: symbol)
      else
        # 兼容数字 ID 和直接 symbol
        Stock.find_by(id: param) || Stock.find_by(symbol: param)
      end

      raise ActiveRecord::RecordNotFound, "未找到股票: #{param}" unless @stock
    end
  end
end