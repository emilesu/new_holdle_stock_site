class UserFavoritesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_stock, only: %i[create destroy]

  def create
    @user_favorite = current_user.favorite!(@stock, rating: rating_param || UserFavorite::DEFAULT_RATING)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to stock_path(@stock), notice: "已收藏 #{@stock.display_name_for_comparison}（#{@user_favorite.rating} 星）" }
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "收藏失败：#{e.message}"
    redirect_to stock_path(@stock)
  end

  def update
    rating = rating_param
    # 非法 / 缺失星级不改库：防止异常请求把已设好的星级覆盖成默认值
    return head 422 if rating.nil?

    # 必须从当前用户的收藏里取，避免拿别人的收藏 id 越权改星级
    @user_favorite = current_user.user_favorites.includes(:stock).find(params[:id])
    @user_favorite.update!(rating: rating)
    @stock = @user_favorite.stock
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: stock_path(@stock), notice: "已更新为 #{@user_favorite.rating} 星" }
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "更新失败：#{e.message}"
    redirect_back fallback_location: stock_path(@user_favorite.stock)
  end

  def destroy
    current_user.unfavorite!(@stock)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: stock_path(@stock), notice: "已取消收藏" }
    end
  end

  private

  def set_stock
    @stock = Stock.find(params[:stock_id])
  end

  # 星级白名单：合法值 1-5 返回整数，缺失 / 数组 / 超范围一律返回 nil 由调用方决定兜底策略
  def rating_param
    rating = params[:rating].to_s.to_i
    UserFavorite::RATINGS.cover?(rating) ? rating : nil
  end
end
