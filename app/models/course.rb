class Course < ApplicationRecord
  has_many :chapters, dependent: :destroy
  has_many :lessons, through: :chapters

  validates :title, presence: true, length: { maximum: 200 }

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort: :asc, id: :asc) }
  scope :accessible_by, ->(user) {
    if user&.is_member?
      all
    else
      where(access_level: [0, nil])
    end
  }

  def published?
    is_published
  end

  def public?
    access_level == 0
  end

  def member_only?
    access_level == 1
  end

  def cover_url
    cover.presence
  end

  def available_to?(user)
    return false unless published?
    return true if public?
    member_only? && user&.is_member?
  end
end