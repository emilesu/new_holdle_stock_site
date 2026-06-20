require "test_helper"

class UserFavoriteTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @stock = stocks(:one)
  end

  test "should create favorite" do
    favorite = UserFavorite.new(user: @user, stock: @stock)
    assert favorite.valid?
  end

  test "should require user" do
    favorite = UserFavorite.new(stock: @stock)
    assert_not favorite.valid?
  end

  test "should require stock" do
    favorite = UserFavorite.new(user: @user)
    assert_not favorite.valid?
  end

  test "should enforce uniqueness of user-stock pair" do
    UserFavorite.create!(user: @user, stock: @stock)
    duplicate = UserFavorite.new(user: @user, stock: @stock)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "已经收藏过该股票"
  end

  test "should allow same user favorite different stocks" do
    stock2 = stocks(:two)
    UserFavorite.create!(user: @user, stock: @stock)
    favorite2 = UserFavorite.new(user: @user, stock: stock2)
    assert favorite2.valid?
  end

  test "should allow different users favorite same stock" do
    user2 = users(:two)
    UserFavorite.create!(user: @user, stock: @stock)
    favorite2 = UserFavorite.new(user: user2, stock: @stock)
    assert favorite2.valid?
  end
end