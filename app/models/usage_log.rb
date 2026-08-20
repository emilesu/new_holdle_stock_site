class UsageLog < ApplicationRecord
  belongs_to :api_key
  belongs_to :user

  validates :request_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[precheck confirmed released] }
end
