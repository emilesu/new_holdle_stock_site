require "test_helper"

class Alipay::PaymentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Plan.create!(plan_code: "starter", name: "尝鲜包", price_cents: 500, quota: 20)
    @app_id = "test-alipay-app"
    ENV["ALIPAY_APP_ID"] = @app_id
  end

  def stub_verify(result)
    stub = Object.new
    stub.define_singleton_method(:verify?) { |_| result }
    Alipay::PaymentsController.send(:remove_const, :ALIPAY_CLIENT) if Alipay::PaymentsController.const_defined?(:ALIPAY_CLIENT, false)
    Alipay::PaymentsController.const_set(:ALIPAY_CLIENT, stub)
  end

  test "notify 验签通过且 TRADE_SUCCESS 标记到账" do
    stub_verify(true)
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, payment_method: "alipay_page")

    post alipay_notify_path, params: {
      app_id: @app_id,
      out_trade_no: order.order_no,
      trade_no: "ali-2001",
      trade_status: "TRADE_SUCCESS",
      total_amount: "5.00"
    }

    assert_response :ok
    assert_equal "success", response.body
    assert order.reload.paid?
    assert_equal "ali-2001", order.alipay_trade_no
  end

  test "notify 重复回调幂等，不重复发放" do
    stub_verify(true)
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, payment_method: "alipay_page")

    params = { app_id: @app_id, out_trade_no: order.order_no, trade_no: "ali-2002", trade_status: "TRADE_SUCCESS", total_amount: "5.00" }
    post alipay_notify_path, params: params
    post alipay_notify_path, params: params

    assert_equal 1, users(:one).api_keys.active.count
    assert_equal 20, users(:one).api_keys.active.first.quota_remaining
  end

  test "notify 金额不匹配拒绝到账" do
    stub_verify(true)
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, payment_method: "alipay_page")

    post alipay_notify_path, params: {
      app_id: @app_id,
      out_trade_no: order.order_no,
      trade_no: "ali-2003",
      trade_status: "TRADE_SUCCESS",
      total_amount: "9.99"
    }

    assert_equal "failure", response.body
    assert_not order.reload.paid?
  end

  test "notify 验签失败拒绝到账" do
    stub_verify(false)
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, payment_method: "alipay_page")

    post alipay_notify_path, params: {
      app_id: @app_id,
      out_trade_no: order.order_no,
      trade_no: "ali-2004",
      trade_status: "TRADE_SUCCESS",
      total_amount: "5.00"
    }

    assert_equal "failure", response.body
    assert_not order.reload.paid?
  end

  test "return_url 已登录跳订单页查看 Key" do
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, payment_method: "alipay_wap")
    sign_in users(:one)
    get alipay_return_path, params: { out_trade_no: order.order_no }
    assert_redirected_to order_path(order)
  end

  test "return_url 未登录渲染公开结果页，不回跳登录页" do
    order = users(:one).orders.create!(title: "尝鲜包", amount_cents: 500, plan_code: "starter", quota: 20, payment_method: "alipay_wap")
    get alipay_return_path, params: { out_trade_no: order.order_no }
    assert_response :success
    assert_match "支付结果确认中", response.body
  end
end