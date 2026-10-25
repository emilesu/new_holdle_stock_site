require "test_helper"

class UserFavoritesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @user = users(:one)
    @stock = stocks(:one)
    @other_stock = stocks(:two)
  end

  class AuthenticatedTest < UserFavoritesControllerTest
    def setup
      super
      sign_in @user
    end

    test "should create favorite with rating" do
      post user_favorites_path, params: { stock_id: @stock.id, rating: 5 },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal 5, @user.user_favorites.find_by(stock_id: @stock.id).rating
    end

    test "should fallback to default rating when rating is invalid" do
      post user_favorites_path, params: { stock_id: @stock.id, rating: 99 },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_equal 3, @user.user_favorites.find_by(stock_id: @stock.id).rating
    end

    test "should update rating via turbo stream" do
      favorite = UserFavorite.create!(user: @user, stock: @stock, rating: 2)
      patch user_favorite_path(favorite), params: { stock_id: @stock.id, rating: 5 },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal 5, favorite.reload.rating
    end

    test "should reject update with invalid rating" do
      favorite = UserFavorite.create!(user: @user, stock: @stock, rating: 2)
      patch user_favorite_path(favorite), params: { stock_id: @stock.id, rating: 99 },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response 422
      assert_equal 2, favorite.reload.rating
    end

    test "duplicate create should update rating instead of raising" do
      UserFavorite.create!(user: @user, stock: @stock, rating: 2)
      assert_no_difference "UserFavorite.count" do
        post user_favorites_path, params: { stock_id: @stock.id, rating: 5 },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_equal 5, @user.user_favorites.find_by(stock_id: @stock.id).rating
    end

    test "should not update another user's favorite" do
      other = UserFavorite.create!(user: users(:two), stock: @stock, rating: 2)
      patch user_favorite_path(other), params: { stock_id: @stock.id, rating: 5 },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :not_found
      assert_equal 2, other.reload.rating
    end

    test "favorite! should update rating when already favorited" do
      @user.favorite!(@stock, rating: 2)
      assert_no_difference "UserFavorite.count" do
        @user.favorite!(@stock, rating: 5)
      end
      assert_equal 5, @user.user_favorites.find_by(stock_id: @stock.id).rating
    end

    test "should create favorite via turbo stream" do
      assert_difference "UserFavorite.count", 1 do
        post user_favorites_path, params: { stock_id: @stock.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", @response.media_type
    end

    test "should create favorite via html" do
      assert_difference "UserFavorite.count", 1 do
        post user_favorites_path, params: { stock_id: @stock.id }
      end
      assert_redirected_to stock_path(@stock)
      follow_redirect!
      assert_response :success
    end

    test "should not create duplicate favorite" do
      UserFavorite.create!(user: @user, stock: @stock)
      assert_no_difference "UserFavorite.count" do
        post user_favorites_path, params: { stock_id: @stock.id }
      end
    end

    test "should destroy favorite via turbo stream" do
      UserFavorite.create!(user: @user, stock: @stock)
      favorite = @user.user_favorites.find_by(stock_id: @stock.id)
      assert_difference "UserFavorite.count", -1 do
        delete user_favorite_path(favorite), params: { stock_id: @stock.id }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", @response.media_type
    end

    test "should destroy favorite via html" do
      UserFavorite.create!(user: @user, stock: @stock)
      favorite = @user.user_favorites.find_by(stock_id: @stock.id)
      assert_difference "UserFavorite.count", -1 do
        delete user_favorite_path(favorite), params: { stock_id: @stock.id }
      end
      assert_redirected_to stock_path(@stock)
    end

    test "favorite? should return correct status" do
      assert_not @user.favorite?(@stock)
      @user.favorite!(@stock)
      assert @user.favorite?(@stock)
    end

    test "favorite! should create record" do
      assert_difference "UserFavorite.count", 1 do
        @user.favorite!(@stock)
      end
    end

    test "unfavorite! should remove record" do
      @user.favorite!(@stock)
      assert_difference "UserFavorite.count", -1 do
        @user.unfavorite!(@stock)
      end
    end

    test "unfavorite! should be safe when not favorited" do
      assert_no_difference "UserFavorite.count" do
        @user.unfavorite!(@stock)
      end
    end

    test "favorites page should render five rating buttons per row" do
      UserFavorite.create!(user: @user, stock: @stock, rating: 4)
      get users_profile_favorites_path
      assert_response :success
      assert_select "#favorite_rating_#{@stock.id}_row button[name='rating']", count: 5
      assert_select "#favorite_rating_#{@stock.id}_row button[name='rating'][value='4'][aria-pressed='true']", count: 1
      # 实心星用市场主题色（fixture 为美股，取蓝色），空心星保持灰色
      assert_select "#favorite_rating_#{@stock.id}_row button.text-blue-600", count: 4
      assert_select "#favorite_rating_#{@stock.id}_row button.text-muted-6", count: 1
      assert_select "#favorite_rating_#{@stock.id}_row[data-favorite-rating-active-class-value='text-blue-600']", count: 1
    end

    test "favorite stars should follow each market theme color" do
      { stocks(:two) => "text-green-600", stocks(:four) => "text-amber-600", @stock => "text-blue-600" }.each do |stock, color|
        UserFavorite.create!(user: @user, stock: stock, rating: 2)
        get users_profile_favorites_path
        assert_select "#favorite_rating_#{stock.id}_row[data-favorite-rating-active-class-value='#{color}']", count: 1
        assert_select "#favorite_rating_#{stock.id}_row button.#{color}", count: 2
      end
    end

    test "stock page should render rating control" do
      get stock_path(@stock)
      assert_response :success
      assert_select "turbo-frame#follow_stock_#{@stock.id} button[name='rating']", count: 5
    end

    test "favorites page should sort by rating desc" do
      UserFavorite.create!(user: @user, stock: @stock, rating: 1)
      UserFavorite.create!(user: @user, stock: @other_stock, rating: 5)
      get users_profile_favorites_path(sort: "rating")
      assert_response :success
      ids = css_select("[data-favorite-row]").map { |row| row["id"] }
      assert_equal ["favorite_card_#{@other_stock.id}", "favorite_card_#{@stock.id}"], ids
    end

    test "should access favorites page" do
      get users_profile_favorites_path
      assert_response :success
    end

    test "favorites page should show paginated favorites" do
      UserFavorite.create!(user: @user, stock: @stock)
      UserFavorite.create!(user: @user, stock: @other_stock)
      get users_profile_favorites_path
      assert_response :success
      assert_select "[id^='favorite_card_']", count: 2
    end

    test "favorites page should show empty state" do
      get users_profile_favorites_path
      assert_response :success
      assert_select "p", text: "暂无收藏的股票"
    end

    test "user model methods integration" do
      assert_not @user.favorite?(@stock)
      @user.favorite!(@stock)
      assert @user.favorite?(@stock)
      @user.unfavorite!(@stock)
      assert_not @user.favorite?(@stock)
    end
  end

  class UnauthenticatedTest < UserFavoritesControllerTest
    test "should redirect to login when creating favorite" do
      post user_favorites_path, params: { stock_id: @stock.id }
      assert_redirected_to new_user_session_path
    end

    test "should redirect to login when destroying favorite" do
      favorite = UserFavorite.create!(user: @user, stock: @stock)
      delete user_favorite_path(favorite), params: { stock_id: @stock.id }
      assert_redirected_to new_user_session_path
    end

    test "should redirect to login when accessing favorites page" do
      get users_profile_favorites_path
      assert_redirected_to new_user_session_path
    end
  end
end