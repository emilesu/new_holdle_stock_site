class Course < ApplicationRecord
  has_many :chapters, dependent: :destroy
  has_many :lessons, through: :chapters

  validates :title, presence: true, length: { maximum: 200 }

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort: :asc, id: :asc) }

  def published?
    is_published
  end

  def public?
    access_level == 0
  end

  def member_only?
    access_level == 1
  end
end