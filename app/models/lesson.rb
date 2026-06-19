class Lesson < ApplicationRecord
  belongs_to :chapter
  has_one :course, through: :chapter

  validates :title, presence: true

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort_num: :asc, id: :asc) }

  def published?
    is_published
  end

  def effective_access_level
    access_level.presence || chapter.effective_access_level
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

  def markdown_html
    return '' if content.blank?
    Commonmarker.to_html(content, options: { unsafe: true })
  rescue => e
    Rails.logger.error "Markdown rendering error: #{e.message}"
    content
  end
end