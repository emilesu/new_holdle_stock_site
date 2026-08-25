class Video < ApplicationRecord
  validates :title, presence: { message: "不能为空" }, length: { maximum: 200, message: "长度不能超过 200 个字符" }
  validates :cover_url, presence: { message: "不能为空" }
  validate :at_least_one_platform_url

  scope :published, -> { where(is_published: true) }
  scope :sorted, -> { order(sort: :asc, published_at: :desc, id: :desc) }

  def published?
    is_published
  end

  private

  def at_least_one_platform_url
    if bilibili_url.blank? && youtube_url.blank?
      errors.add(:base, "B站链接和 YouTube 链接至少填一个")
    end
  end
end
