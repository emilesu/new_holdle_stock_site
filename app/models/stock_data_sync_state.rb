# 股票数据同步状态（每只股票 × 每种数据类型一行）
#
# 用途：
#   1. 后台「数据看板」统计各市场各类型的覆盖率与过期情况
#   2. 后台「批量补抓 / 失败重试」按条件筛出目标股票
# 写入统一走 DataSources::SyncStateRecorder，不要在业务代码里直接 update。
class StockDataSyncState < ApplicationRecord
  belongs_to :stock

  DATA_TYPES = %w[profile financial monthly_bar listing_date].freeze
  DATA_TYPE_NAMES = {
    "profile" => "基础资料",
    "financial" => "财务数据",
    "monthly_bar" => "月K线",
    "listing_date" => "上市日期"
  }.freeze

  STATUSES = %w[pending success failed].freeze

  # 各类数据的「过期」阈值：超过该时长未成功同步即视为过期
  STALE_AFTER = {
    "profile" => 30.days,
    "financial" => 7.days,
    "monthly_bar" => 35.days,
    "listing_date" => 365.days
  }.freeze

  DEFAULT_STALE_AFTER = 30.days

  scope :for_type, ->(data_type) { where(data_type: data_type) }
  scope :for_market, ->(market) { where(market: market) }
  scope :succeeded, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }

  class << self
    def stale_after_for(data_type)
      STALE_AFTER.fetch(data_type.to_s, DEFAULT_STALE_AFTER)
    end

    def data_type_name(data_type)
      DATA_TYPE_NAMES.fetch(data_type.to_s, data_type.to_s)
    end

    # 覆盖率统计：ok=正常 / stale=过期 / never=从未成功（含表中无记录）/ failed=最近一次失败
    # 分母 total 取 Stock 的真实数量，保证「表中没有记录」被算进 never 而不是被漏掉
    def coverage(market:, data_type:, now: Time.current)
      cutoff = now - stale_after_for(data_type)
      sql = sanitize_sql_array([ <<~SQL.squish, { market: market, data_type: data_type, cutoff: cutoff } ])
        SELECT
          count(*) FILTER (WHERE last_success_at IS NOT NULL AND last_success_at >= :cutoff) AS ok_count,
          count(*) FILTER (WHERE last_success_at IS NOT NULL AND last_success_at < :cutoff) AS stale_count,
          count(*) FILTER (WHERE last_success_at IS NOT NULL) AS succeeded_count,
          count(*) FILTER (WHERE status = 'failed') AS failed_count
        FROM stock_data_sync_states
        WHERE market = :market AND data_type = :data_type
      SQL

      row = connection.select_one(sql) || {}
      total = Stock.where(market: market).count
      succeeded = row["succeeded_count"].to_i

      {
        total: total,
        ok: row["ok_count"].to_i,
        stale: row["stale_count"].to_i,
        never: [ total - succeeded, 0 ].max,
        failed: row["failed_count"].to_i
      }
    end

    # 按条件筛选目标股票（供看板批量补抓 / 失败重试使用）
    # scope: all / missing / stale / failed
    def target_stocks(market:, data_type:, scope: "all", now: Time.current)
      return Stock.where(market: market) if scope.blank? || scope.to_s == "all"

      synced = where(market: market, data_type: data_type)
      cutoff = now - stale_after_for(data_type)

      case scope.to_s
      when "failed"
        Stock.where(id: synced.failed.select(:stock_id))
      when "stale"
        Stock.where(id: synced.where(last_success_at: ...cutoff).select(:stock_id))
      when "missing"
        Stock.where(market: market).where.not(id: synced.where.not(last_success_at: nil).select(:stock_id))
      else
        Stock.where(market: market)
      end
    end
  end
end
