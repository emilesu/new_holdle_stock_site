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

  # hero 右栏简介视频区块：用 data-* 稳定钩子断言，不耦合 Tailwind 类名
  test "index hero renders intro video player block" do
    get root_url
    assert_select "[data-controller='video-player']"
    assert_select "[data-video-player-target='cover']"
    assert_select "[data-video-player-target='player']"
    assert_select "[data-video-player-title-value='HOLDLE 网站简介视频']"
  end

  # 外链按钮随 HomeHelper 常量状态自适应：常量填入真实链接后此测试无需修改
  test "index hero video links follow helper config" do
    get root_url
    if HomeHelper::HOME_VIDEO_BVID.blank?
      assert_select "button[disabled]", text: "在 B站观看"
    else
      assert_select "a[href*='bilibili.com']", text: "在 B站观看"
    end
    if HomeHelper::HOME_VIDEO_YOUTUBE_URL.blank?
      assert_select "button[disabled]", text: "在 YouTube 观看"
    else
      assert_select "a[href=?]", HomeHelper::HOME_VIDEO_YOUTUBE_URL, text: "在 YouTube 观看"
    end
  end
end