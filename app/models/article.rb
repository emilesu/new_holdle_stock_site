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

  # 已发布且公开的文章 → 异步推送给百度（新原创内容对 SEO 价值最高；失败不影响保存）
  after_commit :push_to_baidu_if_public, on: [:create, :update], if: -> { ENV["BAIDU_PUSH_TOKEN"].to_s.present? && published? && public? }

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
    MarkdownRenderer.render(content)
  rescue => e
    Rails.logger.error "Article markdown HTML error: #{e.message}"
    content
  end

  private

  # 通知百度抓取已发布公开的文章详情页（异步、静默失败）
  def push_to_baidu_if_public
    BaiduPushJob.perform_later(["https://www.holdle.com/articles/#{id}"])
  rescue => e
    Rails.logger.error "[Article] 文章推送百度失败 ##{id}: #{e.message}"
  end
end
