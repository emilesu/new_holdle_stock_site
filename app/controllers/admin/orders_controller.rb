class Admin::OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @orders = Order.includes(:user).order(created_at: :desc).page(params[:page]).per(50)
  end

  def show
    @order = Order.includes(:user).find(params[:id])
  end
end
