require "test_helper"

class LegalControllerTest < ActionDispatch::IntegrationTest
  test "服务协议页可访问且包含关键章节" do
    get terms_path

    assert_response :success
    assert_match "HOLDLE 用户服务协议", response.body
    assert_match "AI 投研助手", response.body
    assert_match "虚拟服务，一经购买不支持退款", response.body
    assert_match "免责声明", response.body
  end

  test "隐私政策页可访问且包含关键章节" do
    get privacy_path

    assert_response :success
    assert_match "HOLDLE 隐私政策", response.body
    assert_match "我们收集的信息", response.body
    assert_match "不会出售、出租或用于其他商业用途", response.body
    assert_match "未成年人保护", response.body
  end

  test "footer 含服务协议与隐私政策链接" do
    get root_path

    assert_response :success
    assert_select "a[href='#{terms_path}']", text: "服务协议"
    assert_select "a[href='#{privacy_path}']", text: "隐私政策"
  end
end
