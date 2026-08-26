require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index successfully" do
    get root_url
    assert_response :success
  end

  test "index renders case data with Chinese quotes correctly" do
    get root_url
    assert_match "等状态A再买", @response.body
    assert_match "长潜", @response.body
  end

  test "index hero links point to ai-assistant and courses" do
    get root_url
    assert_select "a[href='/ai-assistant']", text: "使用AI助手"
    assert_select "a[href='/courses']", text: "开始学习"
  end

  test "index renders all sections" do
    get root_url
    assert_match "AI RESEARCH ASSISTANT", @response.body
    assert_match "THE METHOD BEHIND AI", @response.body
    assert_match "CASE CLOSED", @response.body
    assert_match "ABOUT THE AUTHOR", @response.body
    assert_match "FAQ", @response.body
  end
end