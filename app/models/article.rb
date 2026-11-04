class Article < ApplicationRecord
  validates :title, presence: true, length: { maximum: 200 }

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort: :asc, published_at: :desc, id: :desc) }
  # 三级门控：0=公开 / 1=学员可见 / 2=会员专属（见 User::TIER_* 与迁移 20261104120000）
  scope :accessible_by, ->(user) {
    tier = user&.content_tier || User::TIER_VISITOR
    return all if tier >= User::TIER_MEMBER
    where(access_level: [nil] + (0..tier).to_a)
  }

  # 已发布且公开的文章 → 异步推送给百度（新原创内容对 SEO 价值最高；失败不影响保存）
  after_commit :push_to_baidu_if_public, on: [:create, :update], if: -> { ENV["BAIDU_PUSH_TOKEN"].to_s.present? && published? && public? }

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

  def available_to?(user)
    return false unless published?
    (user&.content_tier || User::TIER_VISITOR) >= access_level.to_i
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
