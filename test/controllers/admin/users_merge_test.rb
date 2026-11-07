require "test_helper"

# PR-5 后台账号归并入口
class Admin::UsersMergeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two)
    @source = users(:one)
    sign_in @admin
  end

  test "归并表单页可访问" do
    get merge_form_admin_user_path(@source)
    assert_response :success
  end

  test "按邮箱执行归并并跳转目标账号" do
    target = User.create!(email: "merge_target@test.com", password: "password123", nickname: "归并目标")

    assert_difference "MergeLog.count", 1 do
      post merge_admin_user_path(@source), params: { target_email: target.email, note: "工单#9" }
    end
    assert_redirected_to admin_user_path(target)
    assert_predicate @source.reload, :archived?
  end

  test "目标不存在时停留在表单页" do
    assert_no_difference "MergeLog.count" do
      post merge_admin_user_path(@source), params: { target_email: "ghost@test.com" }
    end
    assert_response :success
    assert_not @source.reload.archived?
  end

  test "目标 ID 非法输入不报 500" do
    assert_no_difference "MergeLog.count" do
      post merge_admin_user_path(@source), params: { target_user_id: "abc" }
    end
    assert_response :success
  end

  test "目标填自己时被服务校验拦截" do
    assert_no_difference "MergeLog.count" do
      post merge_admin_user_path(@source), params: { target_user_id: @source.id }
    end
    assert_response :success
    assert_not @source.reload.archived?
  end
end
