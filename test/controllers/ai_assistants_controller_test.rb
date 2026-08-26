require "test_helper"

class AiAssistantsControllerTest < ActionDispatch::IntegrationTest
  test "未登录可访问 AI 助手教程页（公开页）" do
    get ai_assistant_path
    assert_response :success
  end

  test "教程页渲染 5 个 Section，导航含「AI 助手」入口且无「AI-投研」" do
    get ai_assistant_path
    assert_response :success

    # 导航（桌面 + 移动端）存在「AI 助手」链接；「AI-投研」已改名「投研文章」
    assert_select "a[href='/ai-assistant']", text: "AI 助手"
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
