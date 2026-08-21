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
end
