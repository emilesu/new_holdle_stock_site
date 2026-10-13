class QualityProfile < ApplicationRecord
  # 企业质量档案（发布通道契约见 .trae/documents/17/19/20/22 系列）
  # 五态状态机：
  #   draft → pending_review → published → superseded（被新期次取代，历史入口可读）
  #                         ↘ withdrawn（撤回下架，前台仅引导页）
  # withdrawn 永不被自动复活；重新对外必须重新发布并再过闸门。
  STATUSES = %w[draft pending_review published withdrawn superseded].freeze
  STATUS_LABELS = {
    "draft" => "草稿",
    "pending_review" => "待审核",
    "published" => "已发布",
    "withdrawn" => "已撤回",
    "superseded" => "已被取代"
  }.freeze

  # 期次标签与 Stock::PERIOD_TYPE_LABELS 完全一致（年报/中报/一季报/三季报）
  PERIOD_TYPE_LABELS = { "annual" => "年报", "h1" => "中报", "q1" => "一季报", "q3" => "三季报" }.freeze
  PERIOD_FORMAT = /\A\d{4}(年报|中报|一季报|三季报)\z/
  # URL 短码映射（展示层，API 契约仍用中文字符串）
  PERIOD_SHORT = { "A" => "年报", "H1" => "中报", "Q1" => "一季报", "Q3" => "三季报" }.freeze
  PERIOD_TYPE_BY_LABEL = PERIOD_TYPE_LABELS.invert.freeze
  # 状态圆点颜色（后台列表统一使用，避免各视图重复维护）
  STATUS_DOT_CLASSES = { "draft" => "bg-gray-400", "pending_review" => "bg-amber-500",
                         "published" => "bg-green-600", "withdrawn" => "bg-red-500",
                         "superseded" => "bg-blue-400" }.freeze

  belongs_to :stock
  belongs_to :published_by, class_name: "User", optional: true
  has_many :versions, -> { order(version_no: :desc) },
           class_name: "QualityProfileVersion", dependent: :destroy

  validates :period, presence: true, format: { with: PERIOD_FORMAT }
  validates :title, presence: true, length: { maximum: 200 }
  validates :markdown, presence: true
  validates :status, inclusion: { in: STATUSES }

  # 对外可读 = 存在已发布快照且未被撤回。
  # 注意「覆盖待审」场景：status=pending_review 但 published_version_no 仍在 → 读者继续看旧版
  scope :readable, -> { where.not(published_version_no: nil).where.not(status: "withdrawn") }
  scope :published, -> { where(status: "published") }

  def status_label
    STATUS_LABELS[status]
  end

  def status_dot_class
    STATUS_DOT_CLASSES[status] || "bg-gray-400"
  end

  # 对外可见内容 = 已发布版本快照（主表行可能是待审新稿，绝不直接对外）
  # superseded 仍可经历史入口读；withdrawn 不可读（引导页）
  def visible_content
    return nil if status == "withdrawn" || published_version_no.nil?

    versions.find_by(version_no: published_version_no)
  end

  # 期次存在性校验：该股票财务指标中须真实存在对应期次（防孤儿期次幂等失效）
  def self.period_exists?(stock, period)
    return false unless period.to_s.match?(PERIOD_FORMAT)

    year = period[0, 4].to_i
    period_type = PERIOD_TYPE_BY_LABEL[period[4..]]
    return false unless period_type

    stock.financial_indicators
         .where(period_type: period_type)
         .where(report_date: Date.new(year, 1, 1)..Date.new(year, 12, 31))
         .exists?
  end

  # 期次排序键：先年份后披露顺序（同年年报最晚披露→排最前），用于「最新期」判定
  def period_sort_key
    year = period[0, 4].to_i
    type_rank = %w[一季报 中报 三季报 年报].index(period[4..]) || 0
    [year, type_rank]
  end

  # 人工闸门放行：同股票其他 published 转 superseded（不碰 withdrawn），本条对外换文
  def publish!(user)
    # 闸门兜底：内容侧校验门未过的稿件技术上不可发布
    raise "gate_passed 未通过，禁止发布" unless meta["gate_passed"] == true

    ActiveRecord::Base.transaction do
      supersede_other_published
      update!(status: "published", published_version_no: current_version_no,
              published_at: Time.current, published_by: user)
    end
  end

  def withdraw!
    return unless status.in?(%w[published superseded pending_review draft])

    update!(status: "withdrawn", withdrawn_at: Time.current)
  end

  # 回滚 = 人工闸门行为：旧版本内容复制为新版本并直接发布（记审计）
  def rollback_to!(version_no, user)
    snapshot = versions.find_by!(version_no: version_no)
    ActiveRecord::Base.transaction do
      self.current_version_no += 1
      self.title = snapshot.title
      self.markdown = snapshot.markdown
      self.meta = snapshot.meta
      save!
      versions.create!(version_no: current_version_no, title: snapshot.title,
                       markdown: snapshot.markdown, meta: snapshot.meta)
      supersede_other_published
      update!(status: "published", published_version_no: current_version_no,
              published_at: Time.current, published_by: user)
    end
  end

  private

  # 不变式：每只股票至多一条 published。发布/回滚换文前必须先把同股票其他 published 转为 superseded
  def supersede_other_published
    QualityProfile.where(stock_id: stock_id).where(status: "published")
                  .where.not(id: id).update_all(status: "superseded")
  end
end
