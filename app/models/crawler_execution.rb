class CrawlerExecution < ApplicationRecord
  scope :recent, -> { order(executed_at: :desc).limit(10) }
end