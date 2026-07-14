class Admin::OrdersController < Admin::BaseController

  def index
    @orders = Order.includes(:user).order(created_at: :desc).page(params[:page]).per(50)
  end

  def show
    @order = Order.includes(:user).find(params[:id])
  end
end
