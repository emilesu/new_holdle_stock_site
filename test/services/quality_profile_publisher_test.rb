require "test_helper"

# 发布服务：幂等覆盖、状态规则、金字塔分权威回填
class QualityProfilePublisherTest < ActiveSupport::TestCase
  setup do
    @stock = Stock.create!(symbol: "SH603259", name: "药明康德", market: "CN",
                           sector: "医药生物", industry: "医疗服务", exchange: "SHSE",
                           status: "active", pyramid_total_score: 800,
                           last_pyramid_calc_at: Time.zone.parse("2026-10-01 09:00:00"))
  end

  def publish(markdown: "正文", gate: true, meta: {})
    QualityProfilePublisher.call(stock: @stock, period: "2025年报", title: "档案",
                                 markdown: markdown,
                                 meta: { "gate_passed" => gate, "ai_generated" => true }.merge(meta))
  end

  test "同股票同期三次覆盖 = 1 条主表记录 + 3 个版本快照" do
    first, = publish(markdown: "v1")
    publish(markdown: "v2")
    profile, = publish(markdown: "v3")

    assert_equal 1, QualityProfile.where(stock_id: @stock.id, period: "2025年报").count
    assert_equal first.id, profile.id # 幂等：同一行递增
    assert_equal 3, profile.current_version_no
    assert_equal %w[v3 v2 v1], profile.versions.map(&:markdown)
    assert_equal [1, 2, 3], profile.versions.map(&:version_no).sort
  end

  test "gate_passed 决定状态：true→pending_review，false→draft" do
    pending, = publish(gate: true)
    assert_equal "pending_review", pending.status

    draft, = publish(gate: false)
    assert_equal "draft", draft.status

    # 状态规则由服务端强制，任何入参都无法置 published
    _p, = publish(meta: { "status" => "published" })
    assert_equal "pending_review", QualityProfile.find_by(stock_id: @stock.id).status
  end

  test "pyramid_score 与重算时间以库内为权威同源回填" do
    profile, warning = publish(meta: { "pyramid_score" => 750 })

    assert_equal 800, profile.meta["pyramid_score"]
    assert_equal "2026-10-01", profile.meta["pyramid_calc_at"]
    assert_match(/与库内 800 不一致/, warning)
    # 快照同样落库内权威值
    assert_equal 800, profile.versions.last.meta["pyramid_score"]
  end

  test "分数一致或未传时无 warning" do
    _profile, warning = publish(meta: { "pyramid_score" => 800 })
    assert_nil warning

    _profile, warning = publish
    assert_nil warning
  end

  test "symbol 键转字符串：symbol key 入参可正常落 jsonb" do
    profile, = publish(meta: { data_cutoff: "2026-03-23" })
    assert_equal "2026-03-23", profile.meta["data_cutoff"]
  end

  test "撤回后重新发布：withdrawn_at 清空、版本继续递增、状态回到闸门" do
    profile, = publish
    profile.publish!(users(:two))
    profile.withdraw!
    assert_equal "withdrawn", profile.reload.status

    republished, = publish(markdown: "重做稿")
    assert_equal "pending_review", republished.status
    assert_nil republished.withdrawn_at
    assert_equal 2, republished.current_version_no
    # withdrawn 永不自动复活：重新发布清空对外指针，必须再过闸门才能对外
    assert_nil republished.published_version_no
    assert_nil republished.visible_content
  end
end
