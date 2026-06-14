class Course < ApplicationRecord
  has_many :chapters, dependent: :destroy
  has_many :lessons, through: :chapters

  enum status: { draft: "draft", published: "published", archived: "archived" }, _default: "draft"

  validates :title, presence: true, length: { maximum: 200 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
