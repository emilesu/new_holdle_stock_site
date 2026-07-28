class Article < ApplicationRecord
  validates :title, presence: true, length: { maximum: 200 }

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort: :asc, published_at: :desc, id: :desc) }
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

  def available_to?(user)
    return false unless published?
    return true if public?
    member_only? && user&.is_member?
  end

  def markdown_html
    return '' if content.blank?
    html = Commonmarker.to_html(content, options: { unsafe: true, highlight: :html })
    html.gsub!(/<pre\s+style="[^"]*"/, '<pre')
    html.gsub!(/<code\s+style="[^"]*"/, '<code')
    html.gsub!(/<span\s+style="[^"]*"/, '<span')
    html
  rescue => e
    Rails.logger.error "Article markdown HTML error: #{e.message}"
    content
  end
end
