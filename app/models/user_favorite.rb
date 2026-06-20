class UserFavorite < ApplicationRecord
  belongs_to :user
  belongs_to :stock

  validates :user_id, uniqueness: { scope: :stock_id, message: "已经收藏过该股票" }
end