require "test_helper"

# 人工闸门后台：权限 / 预览同管道 / 发布换文 / 撤回 / 回滚
class Admin::ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two) # role: admin
    @stock = Stock.create!(symbol: "SH603259", name: "药明康德", market: "CN", sector: "医药生物",
                           industry: "医疗服务", exchange: "SHSE", status: "active",
                           pyramid_total_score: 800, last_pyramid_calc_at: Time.current)
  end

  def submit(period: "2025年报", markdown: "待审正文", gate: true)
    profile, = QualityProfilePublisher.call(stock: @stock, period: period, title: "档案 #{period}",
                                            markdown: markdown,
                                            meta: { "gate_passed" => gate, "ai_generated" => true })
    profile
  end

  test "非管理员被拒" do
    sign_in users(:one)
    get admin_profiles_path
    assert_response :redirect
  end

  test "index 按状态过滤" do
    pending = submit
    submitted_gate_false = submit(period: "2026年报", gate: false)

    sign_in @admin
    get admin_profiles_path
    assert_response 200
    assert_includes response.body, "档案 2025年报"

    get admin_profiles_path(status: "draft")
    assert_includes response.body, "档案 2026年报"
    refute_includes response.body, "档案 2025年报"
    assert_equal "draft", submitted_gate_false.reload.status
    assert_equal "pending_review", pending.reload.status
  end

  test "show 预览与前台同 sanitize 管道：注入不进 HTML" do
    profile = submit(markdown: "正文\n\n<script>alert(1)</script>\n\n<details><summary>推导</summary>过程</details>")
    sign_in @admin
    get admin_profile_path(profile)
    assert_response 200
    assert_includes response.body, "正文"
    refute_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "<summary>推导</summary>"
  end

  test "闸门未过（gate_passed=false）的稿件无法发布" do
    profile = submit(gate: false)
    sign_in @admin
    post publish_admin_profile_path(profile)
    assert_redirected_to admin_profile_path(profile)
    follow_redirect!
    assert_match "发布失败", response.body
    assert_equal "draft", profile.reload.status
    assert_nil profile.published_version_no
  end

  test "发布成功换文并取代旧期，记录操作人" do
    old_pub = submit(period: "2025年报")
    old_pub.publish!(@admin)
    fresh = submit(period: "2026年报")

    sign_in @admin
    post publish_admin_profile_path(fresh)
    assert_redirected_to admin_profile_path(fresh)

    assert_equal "published", fresh.reload.status
    assert_equal 1, fresh.published_version_no
    assert_equal @admin.id, fresh.published_by_id
    assert_equal "superseded", old_pub.reload.status
  end

  test "撤回后前台下架、后台仍可见" do
    profile = submit
    profile.publish!(@admin)

    sign_in @admin
    post withdraw_admin_profile_path(profile)
    assert_equal "withdrawn", profile.reload.status

    get admin_profile_path(profile)
    assert_response 200
  end

  test "回滚旧版本 = 复制为新版本并直接发布" do
    profile = submit(markdown: "v1 干净稿")
    profile.publish!(@admin)
    QualityProfilePublisher.call(stock: @stock, period: "2025年报", title: "档案 2025年报",
                                 markdown: "v2 问题稿",
                                 meta: { "gate_passed" => true, "ai_generated" => true })

    sign_in @admin
    post rollback_admin_profile_path(profile), params: { version_no: 1 }
    assert_redirected_to admin_profile_path(profile)

    profile.reload
    assert_equal 3, profile.current_version_no
    assert_equal "published", profile.status
    assert_equal "v1 干净稿", profile.visible_content.markdown

    post rollback_admin_profile_path(profile), params: { version_no: 99 }
    follow_redirect!
    assert_match "目标版本不存在", response.body
  end
end
