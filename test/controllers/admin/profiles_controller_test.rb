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

  # ---- 搜索 / 筛选 ----

  test "index 搜索：名称 / 代码（前后缀式大小写不敏感）/ 标题 / 期次" do
    submit(period: "2025年报")
    submit(period: "2026年报")

    sign_in @admin
    { "药明" => true, "603259.SH" => true, "sh603259" => true, "SH603259" => true,
      "2025年报" => true, "不存在关键词" => false, "SZ000001" => false }.each do |q, hit|
      get admin_profiles_path(q: q)
      if hit
        assert_includes response.body, "档案 2025年报", "q=#{q} 应命中"
      else
        refute_includes response.body, "档案 2025年报", "q=#{q} 不应命中"
      end
    end

    get admin_profiles_path(q: "2025年报")
    assert_includes response.body, "档案 2025年报"
    refute_includes response.body, "档案 2026年报"
  end

  test "index 市场与时间范围筛选" do
    cn = submit
    us_stock = Stock.find_or_create_by!(symbol: "AAPL", market: "US") do |s|
      s.name = "Apple"
      s.status = "active"
      s.pyramid_total_score = 100
    end
    us = QualityProfilePublisher.call(stock: us_stock, period: "2025年报", title: "苹果档案",
                                      markdown: "正文", meta: { "gate_passed" => true })[0]

    sign_in @admin
    get admin_profiles_path(market: "US")
    assert_includes response.body, "苹果档案"
    refute_includes response.body, "档案 #{cn.period}"

    get admin_profiles_path(market: "CN")
    assert_includes response.body, "档案 #{cn.period}"
    refute_includes response.body, "苹果档案"

    get admin_profiles_path(range: "7d")
    assert_response 200
    get admin_profiles_path(range: "7d", market: "US")
    assert_includes response.body, "苹果档案"
  end

  # ---- 手动编辑 ----

  test "update 保存为新版本，对外内容不变，再发布才换文" do
    profile = submit(markdown: "原稿")
    profile.publish!(@admin)

    sign_in @admin
    get edit_admin_profile_path(profile)
    assert_response 200

    patch admin_profile_path(profile), params: { profile: { title: "档案 2025年报", markdown: "修正稿" } }
    assert_redirected_to admin_profile_path(profile)

    profile.reload
    assert_equal "pending_review", profile.status
    assert_equal 2, profile.current_version_no
    assert_equal 1, profile.published_version_no
    assert_equal "原稿", profile.visible_content.markdown

    post publish_admin_profile_path(profile)
    profile.reload
    assert_equal "published", profile.status
    assert_equal 2, profile.published_version_no
    assert_equal "修正稿", profile.visible_content.markdown
  end

  test "update 预览模式不落库" do
    profile = submit(markdown: "待审正文")
    sign_in @admin
    patch admin_profile_path(profile),
          params: { profile: { title: "改了标题", markdown: "# 预览\n正文" }, preview: "1" }
    assert_response :unprocessable_content
    assert_includes response.body, "预览渲染效果"
    assert_equal "待审正文", profile.reload.markdown
    assert_equal 1, profile.current_version_no
  end

  test "withdrawn 状态不可进入编辑，直接 POST 亦被重定向" do
    profile = submit
    profile.publish!(@admin)
    profile.withdraw!

    sign_in @admin
    get edit_admin_profile_path(profile)
    assert_redirected_to admin_profile_path(profile)

    patch admin_profile_path(profile), params: { profile: { title: "t", markdown: "m" } }
    assert_redirected_to admin_profile_path(profile)
    assert_equal "withdrawn", profile.reload.status
    assert_equal 1, profile.current_version_no
  end

  test "update 校验失败重渲染保留用户草稿，不回退原值" do
    profile = submit(markdown: "待审正文")
    sign_in @admin
    patch admin_profile_path(profile), params: { profile: { title: "用户新标题", markdown: "" } }
    assert_response :unprocessable_content
    assert_includes response.body, 'value="用户新标题"'
    assert_match "保存失败", response.body
    assert_equal "待审正文", profile.reload.markdown
  end

  # ---- 批量处理 ----

  test "bulk_review 确认页逐条列出摘要并排除不符合条件的稿件" do
    p1 = submit(period: "2025年报")
    draft = submit(period: "2026年报", gate: false)

    sign_in @admin
    post bulk_review_admin_profiles_path, params: { ids: [p1.id, draft.id] }
    assert_response :unprocessable_content
    assert_includes response.body, "批量发布确认"
    assert_includes response.body, "将发布（1 条）"
    assert_includes response.body, "已排除（1 条"
  end

  test "bulk_apply publish 同股票按更新时间升序执行，不变式保持" do
    p1 = submit(period: "2025年报", markdown: "旧期")
    p2 = submit(period: "2026年报", markdown: "新期")

    sign_in @admin
    post bulk_apply_admin_profiles_path, params: { bulk_action: "publish", ids: [p1.id, p2.id] }
    assert_redirected_to admin_profiles_path
    follow_redirect!
    assert_match "成功 2 条", response.body

    # 后发布的 p2 保持 published，p1 被取代 → 每只股票至多一条 published
    assert_equal "published", p2.reload.status
    assert_equal "superseded", p1.reload.status
    assert_equal 1, QualityProfile.where(stock_id: @stock.id, status: "published").count
  end

  test "bulk_apply publish 非待审状态逐条失败不阻断其余" do
    p1 = submit(period: "2025年报")
    draft = submit(period: "2026年报", gate: false)

    sign_in @admin
    post bulk_apply_admin_profiles_path, params: { bulk_action: "publish", ids: [p1.id, draft.id] }
    follow_redirect!
    assert_match "成功 1 条", response.body
    assert_match "失败 1 条", response.body
    assert_equal "published", p1.reload.status
    assert_equal "draft", draft.reload.status
  end

  test "bulk_apply withdraw 批量下架" do
    p1 = submit(period: "2025年报")
    p1.publish!(@admin)
    p2 = submit(period: "2026年报")
    p2.publish!(@admin)

    sign_in @admin
    post bulk_apply_admin_profiles_path, params: { bulk_action: "withdraw", ids: [p1.id, p2.id] }
    follow_redirect!
    assert_match "成功 2 条", response.body
    assert_equal "withdrawn", p1.reload.status
    assert_equal "withdrawn", p2.reload.status
  end

  test "bulk_review 上限按符合条件条数计：20 待审 + 1 草稿仍可通过确认页" do
    ids = Array.new(Admin::ProfilesController::BULK_PUBLISH_LIMIT) { |i| "20#{10 + i}年报" }
                .map { |per| QualityProfilePublisher.call(stock: @stock, period: per, title: "批量 #{per}",
                                                          markdown: "正文", meta: { "gate_passed" => true })[0].id }
    draft = submit(period: "2099年报", gate: false)

    sign_in @admin
    post bulk_review_admin_profiles_path, params: { ids: ids + [draft.id] }
    assert_response :unprocessable_content
    assert_includes response.body, "将发布（20 条）"
    assert_includes response.body, "已排除（1 条"
  end

  test "bulk_review 未选择任何档案时重定向回列表" do
    sign_in @admin
    post bulk_review_admin_profiles_path, params: { ids: [] }
    assert_redirected_to admin_profiles_path
    follow_redirect!
    assert_match "未选择任何档案", response.body
  end

  test "bulk_review 符合条件超过单批上限时重定向拒绝" do
    ids = Array.new(Admin::ProfilesController::BULK_PUBLISH_LIMIT + 1) { |i| "20#{10 + i}年报" }
                .map { |per| QualityProfilePublisher.call(stock: @stock, period: per, title: "批量 #{per}",
                                                          markdown: "正文", meta: { "gate_passed" => true })[0].id }
    sign_in @admin
    post bulk_review_admin_profiles_path, params: { ids: ids }
    assert_redirected_to admin_profiles_path
    follow_redirect!
    assert_match "超过单批上限", response.body
  end

  test "bulk_apply 未选择 / 未知操作 / 超上限均被拒绝" do
    sign_in @admin
    post bulk_apply_admin_profiles_path, params: { bulk_action: "publish", ids: [] }
    follow_redirect!
    assert_match "未选择任何档案", response.body

    p = submit
    post bulk_apply_admin_profiles_path, params: { bulk_action: "delete", ids: [p.id] }
    follow_redirect!
    assert_match "未知批量操作", response.body

    ids = Array.new(Admin::ProfilesController::BULK_PUBLISH_LIMIT + 1) { |i| "20#{10 + i}年报" }
                        .map { |per| QualityProfilePublisher.call(stock: @stock, period: per, title: "批量 #{per}",
                                                                  markdown: "正文", meta: { "gate_passed" => true })[0].id }
    post bulk_apply_admin_profiles_path, params: { bulk_action: "publish", ids: ids }
    follow_redirect!
    assert_match "单批上限", response.body
  end
end
