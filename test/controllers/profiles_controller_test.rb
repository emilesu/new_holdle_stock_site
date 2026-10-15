require "test_helper"

# 前台档案详情：URL 归一化 301 / 会员墙服务端拦截 / 引导页 / 可见性只取已发布快照
class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @stock = Stock.create!(symbol: "SH603259", name: "药明康德", market: "CN", sector: "医药生物",
                           industry: "医疗服务", exchange: "SHSE", status: "active",
                           pyramid_total_score: 800, last_pyramid_calc_at: Time.current)
    @member = users(:one)
    @member.update!(role: "member", member_expire_at: 1.year.from_now)
  end

  # 发布一份对外可见的档案（走真实闸门链路：Publisher → publish!）
  # 默认正文带标题结构：首段「这是档案导语段」在非会员预览可见，首个 ## 后「归母净利拆解正文」仅会员可见
  def publish_profile(period: "2025年报", title: "药明康德 2025 年报档案",
                      markdown: "# 药明康德 2025 年报档案\n\n这是档案导语段。\n\n## 盈利质量\n\n归母净利拆解正文")
    profile, = QualityProfilePublisher.call(stock: @stock, period: period, title: title,
                                            markdown: markdown,
                                            meta: { "gate_passed" => true, "ai_generated" => true,
                                                    "data_cutoff" => "2026-03-23" })
    profile.publish!(users(:two))
    profile
  end

  # ---- URL 归一化 ----

  test "后缀式与小写前缀式 301 归一化到站内格式" do
    get "/archive/603259.SH"
    assert_response 301
    assert_match %r{/archive/SH603259\z}, response.location

    get "/archive/sh603259"
    assert_response 301
    assert_match %r{/archive/SH603259\z}, response.location

    get "/archive/sh603259/2025A"
    assert_response 301
    assert_match %r{/archive/SH603259/2025A\z}, response.location
  end

  test "未入库股票返回 404" do
    get "/archive/SH999999"
    assert_response 404
  end

  # ---- 引导页（免费可见，不触发会员墙） ----

  test "无任何档案时引导页对游客开放" do
    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "尚在制作中"
  end

  test "撤回后游客直接看到引导页而非登录墙" do
    profile = publish_profile
    profile.withdraw!

    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "企业质量档案尚在制作中"
    refute_includes response.body, "归母净利拆解正文"
  end

  test "指定期不可读时回落展示最新可读期" do
    publish_profile(period: "2025年报", markdown: "旧期正文")
    publish_profile(period: "2026年报", markdown: "新期正文")
    QualityProfile.find_by(stock_id: @stock.id, period: "2026中报")&.withdraw!

    # 2026中报从未发布 → 回落最新可读期（2026年报）
    sign_in @member
    get "/archive/SH603259/2026H1"
    assert_response 200
    assert_includes response.body, "新期正文"
  end

  # ---- 会员墙（服务端截断 + 遮罩引导，全文绝不进响应） ----

  test "未登录访问已发布档案 → 遮罩引导页，预览可见但全文不进响应" do
    publish_profile
    get "/archive/SH603259"
    assert_response 200
    # 遮罩引导卡 + 双 CTA（了解权益 / 登录回跳）
    assert_includes response.body, "企业质量档案为会员专属内容"
    assert_includes response.body, "了解会员权益"
    assert_includes response.body, "已有会员？登录"
    # 预览层：首段导语与全文目录标题可见
    assert_includes response.body, "这是档案导语段"
    assert_includes response.body, "盈利质量"
    # 🔴 首个二级标题之后的正文绝不进响应
    refute_includes response.body, "归母净利拆解正文"
  end

  test "登录非会员访问已发布档案 → 遮罩引导页指向升级，全文不进响应" do
    publish_profile
    plain = User.create!(email: "plain@test.com", password: "password123",
                        nickname: "普通用户", onboarded_at: Time.current)
    sign_in plain

    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "企业质量档案为会员专属内容"
    assert_includes response.body, "/join"
    assert_includes response.body, "这是档案导语段"
    # 已登录不再出现登录引导
    refute_includes response.body, "已有会员？登录"
    refute_includes response.body, "归母净利拆解正文"
  end

  # ---- 兜底截断路径（无导语 / 整篇无二级标题）与目录围栏跳过 ----

  test "整篇无二级标题时预览受 400 字硬上限，正文不整体泄露" do
    publish_profile(markdown: "# 标题\n\n#{"这是档案导语段。" * 100}\n\n尾部机密内容")
    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "这是档案导语段"
    refute_includes response.body, "尾部机密内容"
  end

  test "无导语直接以二级标题开头时走兜底截断，超长正文不进响应" do
    publish_profile(markdown: "## 第一节\n\n开头可见内容。\n\n## 第二节\n\n#{"中间段。" * 100}超长机密尾部")
    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "开头可见内容"
    refute_includes response.body, "超长机密尾部"
  end

  test "预览行级剔除会员字段金字塔分与行业名次" do
    publish_profile(markdown: "## 一、档案速览\n\n- **股票名称**：药明康德\n- **数据截止**：2025 年报\n- **金字塔分**：**851 分**\n- **行业名次**：「医疗服务」内第 1 名\n\n## 二、主营业务\n\n#{"正文内容。" * 100}")
    get "/archive/SH603259"
    assert_response 200
    # 公开字段保留作钩子
    assert_includes response.body, "股票名称"
    assert_includes response.body, "数据截止"
    # 🔴 会员数据行级剔除（生产事故回归：速览块金字塔分 851 透过遮罩可见）
    refute_includes response.body, "851 分"
    refute_includes response.body, "行业名次"
    refute_includes response.body, "第 1 名"
  end

  test "代码围栏内的伪标题行不进非会员目录" do
    publish_profile(markdown: "# 标题\n\n这是档案导语段。\n\n## 盈利质量\n\n```\n## 围栏内伪标题\n```\n\n归母净利拆解正文")
    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "盈利质量"
    refute_includes response.body, "围栏内伪标题"
    refute_includes response.body, "归母净利拆解正文"
  end

  test "会员可见正文与元数据条且不含未审新稿" do
    publish_profile
    # 覆盖发布第二稿（待审，未过闸门）——对外必须仍是 v1 旧快照
    draft, = QualityProfilePublisher.call(stock: @stock, period: "2025年报", title: "药明康德 2025 年报档案",
                                          markdown: "未审新稿机密内容",
                                          meta: { "gate_passed" => true, "ai_generated" => true })
    assert_equal "pending_review", draft.status

    sign_in @member
    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "归母净利拆解正文"
    refute_includes response.body, "未审新稿机密内容"
    # 框架层元数据：金字塔分同源回填 + 重算时间 + 常驻免责
    assert_includes response.body, "800"
    assert_includes response.body, "不构成投资建议"
    assert_includes response.body, "AI 生成"
  end

  test "superseded 旧期经历史入口仍可读" do
    publish_profile(period: "2025年报", markdown: "去年档案正文")
    publish_profile(period: "2026年报", markdown: "今年档案正文")

    sign_in @member
    get "/archive/SH603259"
    assert_includes response.body, "今年档案正文"

    get "/archive/SH603259/2025A"
    assert_response 200
    assert_includes response.body, "去年档案正文"
  end

  test "正文经 render_safe：注入脚本不进响应" do
    publish_profile(markdown: "安全正文\n\n<script>alert(1)</script>\n\n<img src=x onerror=alert(2)>")
    sign_in @member
    get "/archive/SH603259"
    assert_response 200
    assert_includes response.body, "安全正文"
    refute_includes response.body, "<script>alert(1)</script>"
    refute_includes response.body, "onerror"
  end
end
