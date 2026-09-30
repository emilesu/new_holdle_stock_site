# 数据质量问题台账
#
# 写入统一走 record!，同一「未处理」的 (stock, data_type, issue_type) 只会有一条记录
# （DB 层 partial unique index 兜底），重复检出只刷新 detected_at 与 detail。
class DataQualityIssue < ApplicationRecord
  belongs_to :stock

  SEVERITIES = %w[info warning error].freeze
  SEVERITY_NAMES = { "info" => "提示", "warning" => "警告", "error" => "严重" }.freeze

  ISSUE_TYPE_NAMES = {
    "month_gap" => "月K缺月",
    "hfq_factor_decrease" => "后复权因子下降",
    "ratio_deviation" => "前后复权常数关系偏离",
    "partial_period" => "财务期次不完整",
    "empty_financials" => "财务关键字段为空",
    "future_report_date" => "财报日期在未来",
    "value_overflow" => "数值溢出被置空"
  }.freeze

  scope :open, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :of_type, ->(data_type) { where(data_type: data_type) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :for_market, ->(market) { where(market: market) }

  class << self
    def issue_type_name(issue_type)
      ISSUE_TYPE_NAMES.fetch(issue_type.to_s, issue_type.to_s)
    end

    # 记录一个问题：已存在同类型的未处理记录时只刷新检出时间与细节
    def record!(stock, data_type, issue_type, severity: "warning", detail: {})
      issue = open.find_or_initialize_by(
        stock_id: stock.id,
        data_type: data_type,
        issue_type: issue_type
      )
      issue.assign_attributes(
        market: stock.market,
        severity: severity,
        detail: detail,
        detected_at: Time.current
      )
      issue.save!
      issue
    end
  end

  def resolve!(resolution = "manual")
    update!(resolved_at: Time.current, resolution: resolution)
  end
end
