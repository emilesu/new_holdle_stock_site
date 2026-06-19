class Chapter < ApplicationRecord
  belongs_to :course
  has_many :lessons, dependent: :destroy

  validates :title, presence: true

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort_num: :asc, id: :asc) }

  def published?
    is_published
  end

  def effective_access_level
    access_level.presence || course.access_level
  end

  def public?
    effective_access_level == 0
  end

  def member_only?
    effective_access_level == 1
  end

  def available_to?(user)
    return false unless published?
    return true if public?
    member_only? && user&.is_member?
  end
end