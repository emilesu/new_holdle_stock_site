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
    html = Commonmarker.to_html(content, options: { unsafe: true })
    html.gsub!(/<img([^>]+)src="([^"]+)"/) do |match|
      attrs = Regexp.last_match(1)
      src = Regexp.last_match(2)
      if src.start_with?('http://', 'https://', '/')
        match
      else
        asset_path = ActionController::Base.helpers.image_path(src)
        "<img#{attrs}src=\"#{asset_path}\""
      end
    end
    html
  rescue => e
    Rails.logger.error "Markdown rendering error: #{e.message}"
    content
  end
end