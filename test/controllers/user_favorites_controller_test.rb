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