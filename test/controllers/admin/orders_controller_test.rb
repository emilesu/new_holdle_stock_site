require "test_helper"

class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two) # role: admin
    sign_in @admin
    @user = users(:one)
  end

  def create_order(user, status: "pending", plan_code: "starter", amount_cents: 500, title: "尝鲜包", quota: 20)
    user.orders.create!(
      title: title,
      amount_cents: amount_cents,
      plan_code: plan_code,
      quota: quota,
      status: status,
      payment_method: "wechat_native",
      paid_at: status == "paid" ? Time.current : nil
    )
  end

  test "管理员可访问订单列表" do
    get admin_orders_path
    assert_response :success
  end

  test "管理员可访问订单详情" do
    order = create_order(@user)
    get admin_order_path(order)
    assert_response :success
    assert_match order.order_no, response.body
  end

  test "非管理员访问订单列表被重定向登录" do
    sign_out @admin
    sign_in @user
    get admin_orders_path
    assert_redirected_to new_user_session_path
  end

  test "按状态筛选：paid 只返回已支付订单" do
    paid = create_order(@user, status: "paid")
    pending = create_order(@user, status: "pending")

    get admin_orders_path, params: { status: "paid" }

    assert_response :success
    assert_match paid.order_no, response.body
    assert_no_match pending.order_no, response.body
  end

  test "关键词搜索：按订单号命中" do
    paid = create_order(@user, status: "paid")
    other = create_order(@user, status: "pending", plan_code: "light", amount_cents: 2000, title: "轻量包", quota: 90)

    get admin_orders_path, params: { q: paid.order_no }

    assert_response :success
    assert_match paid.order_no, response.body
    assert_no_match other.order_no, response.body
  end

  test "关键词搜索：按用户昵称命中" do
    paid = create_order(@user, status: "paid")
    get admin_orders_path, params: { q: @user.nickname }
    assert_response :success
    assert_match paid.order_no, response.body
  end

  test "日期范围筛选生效" do
    old = create_order(@user, status: "paid")
    old.update!(created_at: 10.days.ago)
    recent = create_order(@user, status: "paid")

    get admin_orders_path, params: { from: 5.days.ago.to_date.to_s, to: Date.current.to_s }

    assert_response :success
    assert_match recent.order_no, response.body
    assert_no_match old.order_no, response.body
  end

  test "统计卡片展示已支付金额" do
    create_order(@user, status: "paid", amount_cents: 500)
    create_order(@user, status: "paid", amount_cents: 46_800, plan_code: "member_permanent", title: "永久会员", quota: nil)

    get admin_orders_path

    assert_response :success
    assert_match "¥473", response.body # (500 + 46800) / 100 = 473
  end

  test "订单详情展示用户 Key 状态" do
    order = create_order(@user, status: "paid")
    plain = "hl_" + SecureRandom.hex(8)
    ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      user: @user,
      plan_code: "starter",
      quota_remaining: 20,
      quota_total: 20
    )

    get admin_order_path(order)

    assert_response :success
    assert_match "尝鲜包", response.body
    assert_match "20 次", response.body
  end
end
