module Admin
  class StocksController < BaseController
    before_action :set_stock, only: [:show, :edit, :update, :destroy]

    def index
      @stocks = Stock.includes(:financial_indicators)
      
      if params[:search].present?
        @stocks = @stocks.where("symbol ILIKE ? OR name ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
      end
      
      if params[:market].present? && params[:market] != 'all'
        @stocks = @stocks.where(market: params[:market])
      end
      
      @stocks = @stocks.order(market: :asc, symbol: :asc)
      
      @per_page = 20
      @page = params[:page] ? params[:page].to_i : 1
      @total_count = @stocks.count
      @total_pages = (@total_count.to_f / @per_page).ceil
      @stocks = @stocks.offset((@page - 1) * @per_page).limit(@per_page)
    end

    def show
    end

    def new
      @stock = Stock.new
    end

    def create
      @stock = Stock.new(stock_params)
      
      if @stock.save
        redirect_to admin_stock_path(@stock), notice: '股票添加成功'
      else
        flash[:alert] = "添加失败：#{@stock.errors.full_messages.join(', ')}"
        render :new
      end
    rescue StandardError => e
      flash[:alert] = "添加失败：#{e.message}"
      render :new
    end

    def edit
    end

    def update
      if @stock.update(stock_params)
        redirect_to admin_stock_path(@stock), notice: '股票信息更新成功'
      else
        flash[:alert] = "更新失败：#{@stock.errors.full_messages.join(', ')}"
        render :edit
      end
    rescue StandardError => e
      flash[:alert] = "更新失败：#{e.message}"
      render :edit
    end

    def destroy
      if @stock.destroy
        redirect_to admin_stocks_path, notice: '股票已删除'
      else
        redirect_to admin_stocks_path, alert: "删除失败：#{@stock.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      redirect_to admin_stocks_path, alert: "删除失败：#{e.message}"
    end

    private

    def set_stock
      @stock = Stock.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_stocks_path, alert: '股票不存在'
    end

    def stock_params
      params.require(:stock).permit(:symbol, :name, :market, :industry, :exchange, :status, :sector, :website, :description)
    end
  end
end
