class UserFavoritesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_stock

  def create
    current_user.favorite!(@stock)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to stock_path(@stock), notice: "已收藏 #{@stock.display_name_for_comparison}" }
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "收藏失败：#{e.message}"
    redirect_to stock_path(@stock)
  end

  def destroy
    current_user.unfavorite!(@stock)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to request.referer.presence || stock_path(@stock), notice: "已取消收藏" }
    end
  end

  private

  def set_stock
    @stock = Stock.find(params[:stock_id])
  end
end