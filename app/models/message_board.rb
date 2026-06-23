class MessageBoard < ApplicationRecord
  belongs_to :user

  # 内置固定敏感词列表（模糊匹配包含即拦截，无需数据库表）
  SENSITIVE_WORDS = %w[色情 赌博 刷单 六合彩 代理 加微信 代开 发票 暴力 涉政 辱骂 引流 视频].freeze

  # 作用域
  scope :normal, -> { where(deleted_at: nil) } # 未删除
  scope :deleted, -> { where.not(deleted_at: nil) } # 已软删除
  scope :unread, -> { where(is_read: false).normal }
  scope :my_msg, ->(uid) { where(user_id: uid).normal }

  # 软删除
  def soft_destroy
    update(deleted_at: Time.current)
  end

  # 恢复软删除留言
  def restore
    update(deleted_at: nil)
  end

  # 敏感词校验：包含任意词汇直接不通过
  def self.has_sensitive?(text)
    return false if text.blank?
    SENSITIVE_WORDS.any? { |w| text.include?(w) }
  end
end