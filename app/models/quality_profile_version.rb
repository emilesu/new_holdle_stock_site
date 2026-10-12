class QualityProfileVersion < ApplicationRecord
  belongs_to :quality_profile

  validates :version_no, presence: true, numericality: { greater_than: 0 }
  validates :markdown, presence: true

  def render_html
    MarkdownRenderer.render_safe(markdown)
  end
end
