require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
    Plan.create!(plan_code: "starter", name: "尝鲜包", price_cents: 500, quota: 20)
    Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil, is_member_upgrade: true)
  end

  test "合法 plan 渲染下单页" do
    get new_order_path(plan: "starter")
    assert_response :success
    assert_match "尝鲜包", response.body
  end

  test "缺省 plan 走 468 永久会员（主推入口）" do
    get new_order_path
    assert_response :success
    assert_match "永久会员", response.body
  end

  test "非法 plan 明确报错跳回 join，不再静默回退高价" do
    get new_order_path(plan: "nonexistent_plan")
    assert_redirected_to join_path
    assert_equal "套餐不存在或已下架，请重新选择", flash[:alert]
  end

  test "未登录访问下单页重定向登录" do
    sign_out users(:one)
    get new_order_path
    assert_redirected_to new_user_session_path
  end

  # ===== 支付成功落地页（T7 支付流程改造） =====

  def build_active_key(user, plan_code: "starter", quota: 20)
    plain = "hl_" + SecureRandom.hex(8)
    ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      key_plaintext: plain, # 加密列明文，落地页展示与安装提示词依赖
      user: user,
      plan_code: plan_code,
      quota_remaining: quota,
      quota_total: quota
    )
    plain
  end

  test "支付成功订单渲染落地页：普通用户可见 Key、复制按钮与安装提示词（v1.39.0 起开放）" do
    plain = build_active_key(users(:one))
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, status: "paid")

    get order_path(order)

    assert_response :success
    assert_match "支付成功，已自动开通", response.body
    assert_match plain, response.body
    assert_match "复制 Key", response.body
    assert_match "安装提示词", response.body
    assert_match "ai.holdle.com/mcp", response.body
    assert_match "使用规则（必须遵守）", response.body
  end

  test "支付成功落地页：admin 可见安装提示词（含服务地址）" do
    sign_in users(:two) # admin
    plain = build_active_key(users(:two))
    order = users(:two).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, status: "paid")

    get order_path(order)

    assert_response :success
    assert_match "安装提示词", response.body
    assert_match "ai.holdle.com/mcp", response.body
    assert_match "使用规则（必须遵守）", response.body
    assert_match "holdle_get_rules", response.body
  end

  test "支付成功落地页：无 Key 时提示前往个人中心查看" do
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, status: "paid")

    get order_path(order)

    assert_response :success
    assert_match "支付成功，已自动开通", response.body
    assert_match "请前往个人中心查看你的 Key", response.body
  end

  test "支付成功落地页：明文缺失的 key 自动换新明文展示" do
    # 模拟老 key 无明文（未 backfill）：创建时不传 key_plaintext
    ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest("hl_old_plain"),
      key_prefix: "hl_oldxxx",
      user: users(:one),
      plan_code: "starter",
      quota_remaining: 20,
      quota_total: 20
    )
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, status: "paid")

    get order_path(order)

    assert_response :success
    assert_match "支付成功，已自动开通", response.body
    assert_no_match "hl_old", response.body # 旧 key 不应再出现

    key = users(:one).api_keys.active.first
    assert key.key_plaintext.present? # 已兜底换新明文
    assert_match key.key_plaintext, response.body # 落地页展示新明文
  end

  test "未支付订单仍渲染支付页（回归）" do
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20)

    get order_path(order)

    assert_response :success
    assert_no_match "支付成功，已自动开通", response.body
  end

  # ===== 支付宝下单 =====

  def stub_alipay_client(active: true)
    ENV["ALIPAY_APP_ID"] = "test-alipay-app" if active
    if active
      stub_client = Class.new do
        def page_execute_url(**); "https://openapi.alipay.com/gateway.do?app_id=wap"; end
        def execute(**)
          JSON.generate("alipay_trade_precreate_response" => { "code" => "10000", "qr_code" => "https://qr.alipay.com/test" })
        end
      end.new
      # 在控制器自身命名空间内遮蔽顶层 ALIPAY_CLIENT（false 不查祖先，避免命中顶层 nil）
      OrdersController.send(:remove_const, :ALIPAY_CLIENT) if OrdersController.const_defined?(:ALIPAY_CLIENT, false)
      OrdersController.const_set(:ALIPAY_CLIENT, stub_client)
    end
  end

  test "支付宝下单（手机 UA）生成 wap 订单并跳转" do
    stub_alipay_client
    sign_in users(:one)
    post orders_path, params: {
      plan: "starter",
      payment_method: "alipay",
      authenticity_token: "x"
    }, headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) Safari" }

    order = users(:one).orders.order(:created_at).last
    assert_response :redirect
    assert_redirected_to order_path(order)
    assert_equal "alipay_wap", order.payment_method
    assert order.code_url.present?
  end

  test "支付宝下单（桌面 UA）生成 native 扫码订单并跳转" do
    stub_alipay_client
    sign_in users(:one)
    post orders_path, params: {
      plan: "starter",
      payment_method: "alipay",
      authenticity_token: "x"
    }, headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120" }

    order = users(:one).orders.order(:created_at).last
    assert_response :redirect
    assert_redirected_to order_path(order)
    assert_equal "alipay_native", order.payment_method
    assert_equal "https://qr.alipay.com/test", order.code_url
  end
end
