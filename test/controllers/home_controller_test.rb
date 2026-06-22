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

  test "index renders all sections" do
    get root_url
    assert_match "致七年前认识我的老朋友", @response.body
    assert_match "WHAT WE OFFER", @response.body
    assert_match "METHODOLOGY", @response.body
    assert_match "CASE CLOSED", @response.body
    assert_match "ABOUT THE AUTHOR", @response.body
    assert_match "FAQ", @response.body
  end
end