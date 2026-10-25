class AddRatingToUserFavorites < ActiveRecord::Migration[7.1]
  def change
    add_column :user_favorites, :rating, :integer, default: 3, null: false, comment: "收藏星级 1-5"
    add_check_constraint :user_favorites, "rating BETWEEN 1 AND 5", name: "user_favorites_rating_range"
    add_index :user_favorites, [:user_id, :rating]
  end
end
