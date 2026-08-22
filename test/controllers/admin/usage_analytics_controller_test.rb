require "test_helper"

class Admin::UsageAnalyticsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two) # role: admin
    sign_in @admin
    @user = users(:one)
  end

  def create_log(user, question, status, created_at: Time.current, round_id: nil)
    key = user.api_keys.create!(
      key_hash: Digest::SHA256.hexdigest("hl#{SecureRandom.hex(8)}"),
      key_prefix: "hl_t",
      plan_code: "welcome",
      status: "active",
      quota_remaining: 10,
      quota_total: 10
    )
    UsageLog.create!(
      request_id: SecureRandom.uuid, api_key: key, user: user,
      question: question, status: status, created_at: created_at, round_id: round_id
    )
  end

  test "空数据时显示提示" do
    get admin_usage_analytics_path

    assert_response 200
    assert_match "暂无 confirmed 提问数据", response.body
  end

  test "分类统计与总览正确（含多类命中与状态过滤）" do
    2.times { create_log(@user, "如何看待状态A的突破买入时机", "confirmed") }
    create_log(@user, "选股看ROE和财报", "confirmed")
    create_log(@user, "止损和仓位怎么设置", "confirmed")
    create_log(@user, "方法论与长期理念", "confirmed")
    create_log(@user, "随便聊聊天气", "confirmed")
    create_log(@user, "precheck不算", "precheck")
    create_log(@user, "released不算", "released")
    create_log(@user, "30天前的状态A问题", "confirmed", created_at: 30.days.ago)

    get admin_usage_analytics_path

    assert_response 200
    body = response.body
    # 分类命中：状态A 2 条 / 选股 1 / 止损 1 / 方法论 1 / 其他 1（命中总数 6）
    assert_match "状态A/择时", body
    assert_match "2 条", body
    assert_match "33.3%", body
    assert_match "选股/企业分析", body
    assert_match "交易管理/止损", body
    assert_match "方法论/理念", body
    assert_match "其他/闲聊", body
    # precheck/released 与 30 天前数据均不计入最近提问
    assert_no_match "precheck不算", body
    assert_no_match "released不算", body
    assert_no_match "30天前的状态A问题", body
    # 活跃用户 Top 10 显示昵称
    assert_match "测试用户一", body
  end

  test "时间范围：30 天包含更早数据，7 天不含" do
    create_log(@user, "20天前的止损仓位问题", "confirmed", created_at: 20.days.ago)

    get admin_usage_analytics_path(days: 30)
    assert_response 200
    assert_match "交易管理/止损", response.body

    get admin_usage_analytics_path(days: 7)
    assert_response 200
    assert_match "暂无 confirmed 提问数据", response.body
  end

  test "非法 days 参数回退默认 7 天" do
    create_log(@user, "5天前的择时问题", "confirmed", created_at: 5.days.ago)
    create_log(@user, "8天前的止损问题", "confirmed", created_at: 8.days.ago)

    get admin_usage_analytics_path(days: 99)
    assert_response 200
    # 正确回退到 7 天：5 天前计入、8 天前不计入（若误当 99 天则 8 天前也会出现）
    assert_match "5天前的择时问题", response.body
    assert_no_match "8天前的止损问题", response.body
  end

  test "非管理员访问被重定向" do
    sign_out @admin
    sign_in @user

    get admin_usage_analytics_path

    assert_redirected_to new_user_session_path
  end

  test "总提问数按 round_id 去重（同回合多条 confirmed 算一次）" do
    round = SecureRandom.uuid
    # 同一回合两条 confirmed（模拟并发双扣边界）+ 独立回合一条
    create_log(@user, "状态A突破", "confirmed", round_id: round)
    create_log(@user, "状态A突破", "confirmed", round_id: round)
    create_log(@user, "止损设置", "confirmed", round_id: SecureRandom.uuid)

    get admin_usage_analytics_path

    assert_response 200
    # 总提问数 = 2（round_id 去重后），而非 3；老数据（round_id 为 NULL）回退 request_id 各计一次
    assert_match %r{总提问数</p>\s*<p class="mt-1 text-hl-22 font-bold text-ink">2</p>}, response.body
  end

  test "老数据 round_id 为 NULL 时按 request_id 兜底计数" do
    create_log(@user, "老问题A", "confirmed") # round_id 默认 nil
    create_log(@user, "老问题B", "confirmed")

    get admin_usage_analytics_path

    assert_response 200
    assert_match %r{总提问数</p>\s*<p class="mt-1 text-hl-22 font-bold text-ink">2</p>}, response.body
  end
end
