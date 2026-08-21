require "test_helper"

class PreviewControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "未登录访问预览页一律 404" do
    get preview_home_path
    assert_response :not_found
    get preview_join_path
    assert_response :not_found
    get preview_plans_path
    assert_response :not_found
  end

  test "普通用户访问预览页一律 404（不暴露）" do
    sign_in users(:one)

    get preview_home_path
    assert_response :not_found
    get preview_join_path
    assert_response :not_found
    get preview_plans_path
    assert_response :not_found
  end

  test "admin 可访问全部预览页" do
    sign_in users(:two)

    get preview_home_path
    assert_response :success
    get preview_join_path
    assert_response :success
    get preview_plans_path
    assert_response :success
  end

  test "plans 页在无套餐数据时显示空态提示" do
    sign_in users(:two)

    get preview_plans_path
    assert_response :success
    assert_match "暂无可用套餐", response.body
  end
end
