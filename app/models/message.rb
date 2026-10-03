class Message < ApplicationRecord
  belongs_to :user

  # 发送方枚举：user=用户，admin=站长（大苏）
  enum sender: { user: "user", admin: "admin" }, _default: "user"

  # 内置固定敏感词列表（模糊匹配包含即拦截，无需数据库表）
  SENSITIVE_WORDS = %w[色情 赌博 刷单 六合彩 代理 加微信 代开 发票 暴力 涉政 辱骂 引流 视频].freeze

  # 作用域
  scope :normal, -> { where(deleted_at: nil) } # 未删除
  scope :deleted, -> { where.not(deleted_at: nil) } # 已软删除
  # 用户发给站长、站长尚未读的消息（后台会话列表未读数）
  scope :unread_for_admin, -> { where(sender: "user", is_read: false).normal }
  # 站长回复给用户、用户尚未读的消息（前台悬浮按钮红点数）
  scope :unread_for_user, -> { where(sender: "admin", is_read: false).normal }

  # 软删除
  def soft_destroy
    update(deleted_at: Time.current)
  end

  # 恢复软删除消息
  def restore
    update(deleted_at: nil)
  end

  # 敏感词校验：包含任意词汇直接不通过
  def self.has_sensitive?(text)
    return false if text.blank?
    SENSITIVE_WORDS.any? { |w| text.include?(w) }
  end
end
