class MergeLog < ApplicationRecord
  CHANNELS = %w[admin claim].freeze

  validates :source_user_id, :target_user_id, presence: true
  validates :channel, inclusion: { in: CHANNELS }

  def payload_json
    @payload_json ||= JSON.parse(payload.to_s.presence || "{}")
  rescue JSON::ParserError
    {}
  end
end
