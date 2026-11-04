class Course < ApplicationRecord
  has_many :chapters, dependent: :destroy
  has_many :lessons, through: :chapters

  validates :title, presence: true, length: { maximum: 200 }

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort: :asc, id: :asc) }
  # 三级门控：0=公开 / 1=学员可见 / 2=会员专属（见 User::TIER_* 与迁移 20261104120000）
  scope :accessible_by, ->(user) {
    tier = user&.content_tier || User::TIER_VISITOR
    return all if tier >= User::TIER_MEMBER
    where(access_level: [nil] + (0..tier).to_a)
  }

  def published?
    is_published
  end

  def public?
    access_level.to_i == User::TIER_VISITOR
  end

  def student_only?
    access_level.to_i == User::TIER_STUDENT
  end

  def member_only?
    access_level.to_i == User::TIER_MEMBER
  end

  def cover_url
    cover.presence
  end

  def available_to?(user)
    return false unless published?
    (user&.content_tier || User::TIER_VISITOR) >= access_level.to_i
  end
end