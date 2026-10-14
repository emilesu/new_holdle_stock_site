require "test_helper"

# 企业质量档案五态状态机 + 可见性语义 + 期次校验
class QualityProfileTest < ActiveSupport::TestCase
  setup do
    @stock = Stock.create!(symbol: "SH603259", name: "药明康德", market: "CN",
                           sector: "医药生物", industry: "医疗服务", exchange: "SHSE",
                           status: "active", pyramid_total_score: 800)
  end

  def build_profile(period: "2025年报", status: "draft", gate: true,
                    current_version_no: 1, published_version_no: nil, markdown: "正文")
    QualityProfile.create!(stock: @stock, period: period, title: "档案 #{period}",
                           markdown: markdown, status: status,
                           current_version_no: current_version_no,
                           published_version_no: published_version_no,
                           meta: { "gate_passed" => gate })
  end

  def add_version(profile, version_no, markdown:)
    QualityProfileVersion.create!(quality_profile: profile, version_no: version_no,
                                  title: profile.title, markdown: markdown, meta: profile.meta)
  end

  # ---- 校验 ----

  test "period 非法格式被拒绝（半年报/缺位/英文短码）" do
    %w[2025半年报 25年报 2025Q1].each do |bad|
      p = QualityProfile.new(stock: @stock, period: bad, title: "标题", markdown: "正文", status: "draft")
      assert_not_predicate p, :valid?, "#{bad} 不应通过校验"
    end
  end

  # ---- 期次存在性 ----

  test "period_exists? 依据财务指标真实期次" do
    assert_not QualityProfile.period_exists?(@stock, "2025年报")

    fr = FinancialReport.create!(stock: @stock, report_date: Date.new(2025, 12, 31),
                                 report_type: "CN_ANNUAL", market: "CN",
                                 period_type: "annual", currency: "CNY")
    FinancialIndicator.create!(financial_report: fr, stock: @stock,
                               report_date: Date.new(2025, 12, 31), market: "CN",
                               period_type: "annual")

    assert QualityProfile.period_exists?(@stock, "2025年报")
    assert_not QualityProfile.period_exists?(@stock, "2025中报")   # 孤儿期次
    assert_not QualityProfile.period_exists?(@stock, "2026年报")   # 别的年份
    assert_not QualityProfile.period_exists?(@stock, "2025半年报") # 非法标签
  end

  # ---- 可见性语义（对外只取已发布快照） ----

  test "visible_content：覆盖待审期间旧版继续可见" do
    profile = build_profile(status: "pending_review", current_version_no: 2, published_version_no: 1,
                            markdown: "新稿未审")
    add_version(profile, 1, markdown: "旧版已发布")

    content = profile.visible_content
    assert_equal 1, content.version_no
    assert_equal "旧版已发布", content.markdown
  end

  test "visible_content：withdrawn 或从未发布均不可见" do
    never = build_profile(status: "draft")
    assert_nil never.visible_content

    withdrawn = build_profile(period: "2026一季报", status: "withdrawn", published_version_no: 1)
    add_version(withdrawn, 1, markdown: "曾发布")
    assert_nil withdrawn.visible_content

    superseded = build_profile(period: "2026中报", status: "superseded", published_version_no: 1)
    add_version(superseded, 1, markdown: "被取代仍可读")
    assert_equal "被取代仍可读", superseded.visible_content.markdown
  end

  test "readable scope 排除未发布与撤回" do
    build_profile(period: "2025年报", status: "pending_review", current_version_no: 2, published_version_no: 1)
    build_profile(period: "2026一季报", status: "draft")
    build_profile(period: "2026中报", status: "withdrawn", published_version_no: 1)
    assert_equal %w[2025年报], QualityProfile.readable.map(&:period)
  end

  # ---- 发布闸门 ----

  test "publish! 拒绝 gate_passed 未通过的稿件" do
    profile = build_profile(gate: false, current_version_no: 1)
    add_version(profile, 1, markdown: "校验门未过")
    assert_raise(RuntimeError) { profile.publish!(users(:two)) }
    assert_equal "draft", profile.reload.status
  end

  test "publish! 换文并将同股票旧 published 转 superseded，不碰 withdrawn" do
    old_pub = build_profile(period: "2025年报", status: "published", published_version_no: 1)
    add_version(old_pub, 1, markdown: "旧")
    gone = build_profile(period: "2025中报", status: "withdrawn", published_version_no: 1)
    add_version(gone, 1, markdown: "撤")
    fresh = build_profile(period: "2026年报", current_version_no: 1)
    add_version(fresh, 1, markdown: "新")

    fresh.publish!(users(:two))

    assert_equal "published", fresh.reload.status
    assert_equal 1, fresh.published_version_no
    assert_not_nil fresh.published_at
    assert_equal users(:two).id, fresh.published_by_id
    assert_equal "superseded", old_pub.reload.status
    assert_equal "withdrawn", gone.reload.status
  end

  test "withdraw! 置撤回并记录时间" do
    profile = build_profile(status: "published", published_version_no: 1)
    profile.withdraw!
    assert_equal "withdrawn", profile.reload.status
    assert_not_nil profile.withdrawn_at
  end

  # ---- 回滚 ----

  test "rollback_to! 复制旧快照为新版本并直接发布" do
    profile = build_profile(status: "pending_review", current_version_no: 2, published_version_no: 1,
                            markdown: "问题新稿")
    add_version(profile, 1, markdown: "干净旧稿")

    profile.rollback_to!(1, users(:two))

    assert_equal "published", profile.reload.status
    assert_equal 3, profile.current_version_no
    assert_equal 3, profile.published_version_no
    assert_equal "干净旧稿", profile.visible_content.markdown
    assert_equal "干净旧稿", profile.versions.find_by(version_no: 3).markdown
  end

  test "rollback_to! 目标版本不存在时抛 RecordNotFound" do
    profile = build_profile(current_version_no: 1)
    assert_raise(ActiveRecord::RecordNotFound) { profile.rollback_to!(99, users(:two)) }
  end

  test "rollback_to! 换文并将同股票旧 published 转 superseded" do
    old_pub = build_profile(period: "2025年报", status: "published", published_version_no: 1)
    add_version(old_pub, 1, markdown: "旧发布稿")
    fresh = build_profile(period: "2026年报", status: "pending_review",
                          current_version_no: 2, published_version_no: 1, markdown: "问题新稿")
    add_version(fresh, 1, markdown: "干净旧稿")

    fresh.rollback_to!(1, users(:two))

    assert_equal "published", fresh.reload.status
    assert_equal "superseded", old_pub.reload.status
  end

  # ---- 手动编辑 ----

  test "manual_edit! 生成新版本快照留痕，主表 meta 不被污染" do
    profile = build_profile(status: "pending_review", current_version_no: 2)
    add_version(profile, 2, markdown: "原始正文")

    profile.manual_edit!(title: "编辑后标题", markdown: "编辑后正文", user: users(:two))

    assert_equal 3, profile.current_version_no
    assert_equal "编辑后标题", profile.title
    snap = profile.versions.find_by(version_no: 3)
    assert_equal "编辑后正文", snap.markdown
    assert snap.meta["manual_edited_by"].present?
    assert_nil profile.reload.meta["manual_edited_by"]
  end

  test "manual_edit! published 稿转覆盖待审，对外仍读旧快照" do
    profile = build_profile(status: "published", current_version_no: 1, published_version_no: 1)
    add_version(profile, 1, markdown: "旧版已发布")

    profile.manual_edit!(title: profile.title, markdown: "修正后正文", user: users(:two))

    assert_equal "pending_review", profile.status
    assert_equal 1, profile.published_version_no
    assert_equal "旧版已发布", profile.visible_content.markdown
  end

  test "manual_edit! draft 编辑后仍是 draft；withdrawn/superseded 不可编辑；空内容拒绝" do
    draft = build_profile(status: "draft", gate: false)
    draft.manual_edit!(title: "标题", markdown: "正文", user: users(:two))
    assert_equal "draft", draft.status

    withdrawn = build_profile(period: "2026一季报", status: "withdrawn", published_version_no: 1)
    assert_raise(RuntimeError) { withdrawn.manual_edit!(title: "t", markdown: "m", user: users(:two)) }

    superseded = build_profile(period: "2026中报", status: "superseded", published_version_no: 1)
    assert_raise(RuntimeError) { superseded.manual_edit!(title: "t", markdown: "m", user: users(:two)) }

    assert_raise(RuntimeError) { draft.manual_edit!(title: "  ", markdown: "正文", user: users(:two)) }
    assert_raise(RuntimeError) { draft.manual_edit!(title: "标题", markdown: "", user: users(:two)) }
  end

  # ---- 期次排序（最新期判定） ----

  test "period_sort_key 先年份后披露顺序（年报同年最前）" do
    sort_key = ->(p) { QualityProfile.new(stock: @stock, period: p, title: "t", markdown: "m").period_sort_key }
    ordered = %w[2025一季报 2025中报 2025三季报 2025年报 2026一季报].sort_by(&sort_key)
    assert_equal %w[2025一季报 2025中报 2025三季报 2025年报 2026一季报], ordered
    assert_equal "2025年报", %w[2025一季报 2025中报 2025三季报 2025年报].max_by(&sort_key)
  end
end
