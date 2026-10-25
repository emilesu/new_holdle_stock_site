class UserFavorite < ApplicationRecord
  # 收藏星级：5 星为最高重视，1 星为最低
  RATINGS = (1..5).freeze
  DEFAULT_RATING = 3

  belongs_to :user
  belongs_to :stock

  validates :user_id, uniqueness: { scope: :stock_id, message: "已经收藏过该股票" }
  validates :rating, inclusion: { in: RATINGS }
end