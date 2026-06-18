class Lesson < ApplicationRecord
  belongs_to :chapter
  has_one :course, through: :chapter

  validates :title, presence: true

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort_num: :asc, id: :asc) }

  def published?
    is_published
  end

  def markdown_html
    return '' if content.blank?
    options = [:DEFAULT, :UNSAFE]
    extensions = [:DEFAULT, :TABLE, :STRIKETHROUGH, :FENCED_CODE_BLOCKS]
    doc = CommonMarker.render_doc(content, options, extensions)
    doc.to_html
  rescue => e
    Rails.logger.error "Markdown rendering error: #{e.message}"
    content
  end
end