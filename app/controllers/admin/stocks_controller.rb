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
      symbol = @stock&.symbol
      stock_id = @stock&.id
      Rails.logger.info "[RecalculatePyramid] 开始: stock=#{symbol}(id=#{stock_id}), params_id=#{params[:id]}"

      # 验证 stock 存在
      unless @stock
        Rails.logger.error "[RecalculatePyramid] 股票不存在: id=#{params[:id]}"
        return render_error_turbo("股票不存在")
      end

      # 记录计算前的状态
      before_score = @stock.pyramid_total_score
      before_calc_at = @stock.last_pyramid_calc_at
      Rails.logger.info "[RecalculatePyramid] 计算前状态: score=#{before_score}, last_calc_at=#{before_calc_at}"

      result = DataSources::StockPyramidService.call(@stock)

      Rails.logger.info "[RecalculatePyramid] Service返回: stock=#{symbol}, result=#{result.inspect}"

      # 重新加载获取最新数据
      reloaded = @stock.reload
      after_score = reloaded.pyramid_total_score
      after_calc_at = reloaded.last_pyramid_calc_at
      Rails.logger.info "[RecalculatePyramid] 计算后状态: score=#{after_score}, last_calc_at=#{after_calc_at}, 分数变化=#{before_score != after_score}"

      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace(
              "stock-#{stock_id}",
              partial: 'admin/stocks/stock_row',
              locals: { stock: reloaded }
            )
          ]

          # 添加状态提示消息
          if result[:success]
            if before_score != after_score
              msg = "✅ #{symbol} 分数已更新: #{before_score} → #{after_score}"
              Rails.logger.info "[RecalculatePyramid] #{msg}"
            else
              msg = "ℹ️ #{symbol} 分数未变化 (#{after_score})，已更新时间戳"
              Rails.logger.info "[RecalculatePyramid] #{msg}"
            end
            streams << turbo_stream.update("pyramid-status-#{stock_id}", html: status_badge(:success, msg))
          else
            msg = "❌ #{symbol} 计算失败: #{result[:error]}"
            Rails.logger.error "[RecalculatePyramid] #{msg}"
            streams << turbo_stream.update("pyramid-status-#{stock_id}", html: status_badge(:error, msg))
          end

          render turbo_stream: streams
        end
        format.html do
          redirect_to admin_stocks_path, notice: result[:success] ? '计算成功' : "计算失败: #{result[:error]}"
        end
      end
    rescue => e
      Rails.logger.error "[RecalculatePyramid] 异常: stock=#{@stock&.symbol}, error=#{e.message}"
      Rails.logger.error e.backtrace&.first(5)&.join("\n")
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "stock-#{@stock&.id}",
              partial: 'admin/stocks/stock_row',
              locals: { stock: @stock&.reload }
            ),
            turbo_stream.update("pyramid-status-#{@stock&.id}", html: status_badge(:error, "异常: #{e.message}"))
          ]
        end
        format.html do
          redirect_to admin_stocks_path, alert: "计算失败: #{e.message}"
        end
      end
    end

    private

    def status_badge(type, message)
      color = type == :success ? 'bg-green-50 text-green-700 border-green-200' : 'bg-red-50 text-red-700 border-red-200'
      %(<span class="inline-flex items-center text-hl-12 px-2 py-0.5 rounded border #{color} ml-2">#{ERB::Util.html_escape(message)}</span>)
    end

    def render_error_turbo(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("pyramid-status-global", html: status_badge(:error, message))
          ]
        end
        format.html { redirect_to admin_stocks_path, alert: message }
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