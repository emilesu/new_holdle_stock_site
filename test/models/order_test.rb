require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    Plan.create!(plan_code: "welcome", name: "新用户体验", price_cents: 0, quota: 15)
    Plan.create!(plan_code: "starter", name: "尝鲜包", price_cents: 500, quota: 20)
    Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil, is_member_upgrade: true)
  end

  def build_order(user, plan_code: "starter", quota: 20)
    plan = Plan.find_by!(plan_code: plan_code)
    Order.create!(
      user: user,
      product_code: plan_code,
      plan_code: plan_code,
      quota: quota,
      title: plan.name,
      amount_cents: plan.price_cents,
      payment_method: "wechat_native"
    )
  end

  test "首次购买次数包：支付成功生成新 key（starter 20 次）" do
    user = users(:one)

    order = build_order(user, plan_code: "starter", quota: 20)
    order.mark_as_paid!(transaction_id: "tx-1", notify_data: {})

    key = user.api_keys.active.first
    assert key.present?, "支付成功后应有 active key"
    assert_equal "starter", key.plan_code
    assert_equal 20, key.quota_remaining
  end

  test "续费：已有 active key 加次数，不新开 key" do
    user = users(:one)
    plain = "hl_" + SecureRandom.hex(8)
    first_key = ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      user: user,
      plan_code: "starter",
      quota_remaining: 10,
      quota_total: 20
    )

    order = build_order(user, plan_code: "starter", quota: 20)
    order.mark_as_paid!(transaction_id: "tx-2", notify_data: {})

    assert_equal 1, user.api_keys.active.count, "续费不应新开 key"
    assert_equal 30, first_key.reload.quota_remaining, "次数应叠加到现有 key"
  end

  test "购买 468：无 key 用户生成无限次会员 key 并升级会员" do
    user = users(:one)

    order = build_order(user, plan_code: "member_permanent", quota: nil)
    order.mark_as_paid!(transaction_id: "tx-3", notify_data: {})

    assert user.reload.member?, "支付后应升级为会员"
    key = user.api_keys.active.first
    assert_equal "member_permanent", key.plan_code
    assert_nil key.quota_remaining, "会员 key 应为无限次"
  end

  test "购买 468：已有有限次 key 转为无限次（同一把 key）" do
    user = users(:one)
    plain = "hl_" + SecureRandom.hex(8)
    first_key = ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      user: user,
      plan_code: "starter",
      quota_remaining: 10,
      quota_total: 20
    )

    order = build_order(user, plan_code: "member_permanent", quota: nil)
    order.mark_as_paid!(transaction_id: "tx-4", notify_data: {})

    assert_equal 1, user.api_keys.active.count, "不应新开 key"
    assert_equal first_key.id, user.api_keys.active.first.id, "应为同一把 key"
    assert_equal "member_permanent", first_key.reload.plan_code
    assert_nil first_key.quota_remaining
  end

  test "幂等：重复 mark_as_paid! 不重复发放" do
    user = users(:one)
    order = build_order(user, plan_code: "starter", quota: 20)

    order.mark_as_paid!(transaction_id: "tx-5", notify_data: {})
    order.mark_as_paid!(transaction_id: "tx-5", notify_data: {})

    assert_equal 1, user.api_keys.active.count
    assert_equal 20, user.api_keys.active.first.quota_remaining
  end

  test "历史订单（无 plan_code）按 member_permanent 兜底处理" do
    user = users(:one)
    order = Order.create!(
      user: user,
      product_code: "member_permanent",
      title: "HOLD LE 永久会员",
      amount_cents: 46_800,
      payment_method: "wechat_native"
    )

    order.mark_as_paid!(transaction_id: "tx-6", notify_data: {})

    assert user.reload.member?
    assert_equal "member_permanent", user.api_keys.active.first.plan_code
  end

  test "admin 用户支付会员单不会被降级为 member" do
    admin = users(:two) # role: admin
    order = build_order(admin, plan_code: "member_permanent", quota: nil)

    order.mark_as_paid!(transaction_id: "tx-7", notify_data: {})

    assert admin.reload.admin?, "管理员不应被支付回调降级"
    assert_equal "member_permanent", admin.api_keys.active.first.plan_code
  end

  # ===== 支付宝渠道 =====

  def build_alipay_order(user, plan_code: "starter", quota: 20)
    plan = Plan.find_by!(plan_code: plan_code)
    Order.create!(
      user: user,
      product_code: plan_code,
      plan_code: plan_code,
      quota: quota,
      title: plan.name,
      amount_cents: plan.price_cents,
      payment_method: "alipay_native"
    )
  end

  test "支付宝订单支付成功存入 alipay_trade_no 并发放 key" do
    user = users(:one)
    order = build_alipay_order(user)

    order.mark_as_paid!(transaction_id: "ali-trade-1", notify_data: {})

    key = user.api_keys.active.first
    assert key.present?, "支付成功后应有 active key"
    assert_equal "starter", key.plan_code
    assert_equal 20, key.quota_remaining
    assert_nil order.wechat_transaction_id, "支付宝订单不应写微信交易号"
    assert_equal "ali-trade-1", order.alipay_trade_no
  end

  test "支付宝订单幂等：重复 mark_as_paid! 不重复发放" do
    user = users(:one)
    order = build_alipay_order(user)

    order.mark_as_paid!(transaction_id: "ali-trade-2", notify_data: {})
    order.mark_as_paid!(transaction_id: "ali-trade-2", notify_data: {})

    assert_equal 1, user.api_keys.active.count
    assert_equal 20, user.api_keys.active.first.quota_remaining
  end

  test "支付宝手机唤起订单（alipay_wap）支付成功同样到账" do
    user = users(:one)
    plan = Plan.find_by!(plan_code: "starter")
    order = Order.create!(
      user: user,
      product_code: "starter",
      plan_code: "starter",
      quota: 20,
      title: plan.name,
      amount_cents: plan.price_cents,
      payment_method: "alipay_wap"
    )

    order.mark_as_paid!(transaction_id: "ali-trade-3", notify_data: {})

    assert order.paid?
    assert_equal "ali-trade-3", order.alipay_trade_no
  end
end
