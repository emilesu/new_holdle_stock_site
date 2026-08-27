class UsageLog < ApplicationRecord
  # round_id_source 取值：调用方显式传入 / Rails 兜底生成（调用方未传 round_id）
  ROUND_ID_SOURCE_CALLER = "caller"
  ROUND_ID_SOURCE_GENERATED = "generated"

  belongs_to :api_key
  belongs_to :user

  validates :request_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[precheck confirmed released merged] }
  validates :tool_name, length: { maximum: 255 }
end
