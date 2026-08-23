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
    get preview_ai_assistant_path
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
    get preview_ai_assistant_path
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
    get preview_ai_assistant_path
    assert_response :success
  end

  test "plans 页在无套餐数据时显示空态提示" do
    sign_in users(:two)

    get preview_plans_path
    assert_response :success
    assert_match "暂无可用套餐", response.body
  end

  test "ai_assistant 教程页渲染 5 个 Section 且导航已改名投研文章" do
    sign_in users(:two)

    get preview_ai_assistant_path
    assert_response :success

    # 导航「AI-投研」已改名「投研文章」（桌面 + 移动端两处）
    assert_match "投研文章", response.body
    assert_no_match "AI-投研", response.body

    # 5 个 Section 关键内容齐全
    assert_match "把 HOLDLE 方法论，装进你的 AI 工具", response.body   # S1 Hero
    assert_match "安装方法", response.body                              # S2 安装
    assert_match "怎么问，AI 才能帮到你", response.body                 # S3 如何问
    assert_match "常见问题", response.body                              # S4 FAQ
    assert_match "风险声明", response.body                              # S5 风险+反馈
  end
end
