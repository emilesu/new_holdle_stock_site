require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "show renders own thread and excludes other users messages" do
    get messages_path
    assert_response :success
    assert_includes @response.body, messages(:user_msg_read).content
    assert_includes @response.body, messages(:admin_msg_unread).content
    assert_includes @response.body, "该消息已被管理员隐藏" # 隐藏消息显示占位
    assert_not_includes @response.body, messages(:deleted_msg).content # 隐藏消息内容不外泄
    assert_not_includes @response.body, messages(:user_msg_unread).content # 他人会话不泄露
  end

  test "show marks admin replies read clearing badge" do
    assert_not messages(:admin_msg_unread).reload.is_read
    get messages_path
    assert messages(:admin_msg_unread).reload.is_read
  end

  test "create appends message to thread" do
    assert_difference -> { Message.where(user_id: @user.id).count }, 1 do
      post messages_path, params: { content: "你好大苏" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes @response.body, "你好大苏"
  end

  test "create blocked by sensitive words saves nothing" do
    assert_no_difference "Message.count" do
      post messages_path, params: { content: "赌博相关的策略怎么走" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_includes @response.body, "违规词汇"
  end

  test "create rejects blank content" do
    assert_no_difference "Message.count" do
      post messages_path, params: { content: "   " },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_includes @response.body, "不能为空"
  end

  test "earlier returns older page by cursor" do
    newest = @user.messages.create!(sender: "user", content: "最新一条消息")
    get earlier_messages_path(before_at: newest.created_at.iso8601(6), before_id: newest.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, messages(:user_msg_read).content
    assert_not_includes @response.body, "最新一条消息"
  end

  test "earlier rejects invalid cursor" do
    get earlier_messages_path(before_id: 0),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :bad_request
  end

  test "unauthenticated user is redirected to sign in" do
    sign_out @user
    get messages_path
    assert_redirected_to new_user_session_path
  end
end
