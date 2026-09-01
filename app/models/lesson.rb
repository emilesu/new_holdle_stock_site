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
    html = MarkdownRenderer.render(content)
    html.gsub!(/<img([^>]+)src="([^"]+)"/) do |match|
      attrs = Regexp.last_match(1)
      src = Regexp.last_match(2)
      if src.start_with?('http://', 'https://', '/')
        match
      else
        begin
          # Commonmarker 会把中文等非 ASCII 路径做 URL 编码，而 sprockets manifest key 是原文，
          # 查找前需先解码，避免 image_path 命中失败导致相对路径残留（生成 /lessons/... 404）
          decoded_src = URI::DEFAULT_PARSER.unescape(src)
          asset_path = ActionController::Base.helpers.image_path(decoded_src)
          "<img#{attrs}src=\"#{asset_path}\""
        rescue
          Rails.logger.warn "Missing asset: #{decoded_src || src}"
          match
        end
      end
    end
    html
  rescue => e
    Rails.logger.error "Markdown rendering error: #{e.message}"
    content
  end
end