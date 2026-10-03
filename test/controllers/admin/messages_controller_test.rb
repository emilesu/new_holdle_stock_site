require "test_helper"

class Admin::MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two)
    sign_in @admin
  end

  test "index lists conversations grouped by user with unread badge" do
    get admin_messages_path
    assert_response :success
    # 用户二有一条未读 user 消息 → 显示 1 未读徽章与预览
    assert_includes @response.body, "这是未读留言二"
    assert_includes @response.body, "1 未读"
  end

  test "show renders thread and marks user messages read" do
    assert_not messages(:user_msg_unread).reload.is_read
    get admin_message_thread_path(users(:two).id)
    assert_response :success
    assert_includes @response.body, messages(:user_msg_unread).content
    assert messages(:user_msg_unread).reload.is_read
  end

  test "reply creates admin message visible in thread" do
    assert_difference -> { Message.where(sender: "admin").count }, 1 do
      post admin_reply_message_thread_path(users(:one).id), params: { reply: "收到，马上处理" }
    end
    assert_redirected_to admin_message_thread_path(users(:one).id, page: 1)
    get admin_message_thread_path(users(:one).id)
    assert_includes @response.body, "收到，马上处理"
  end

  test "reply with blank content creates nothing" do
    assert_no_difference "Message.count" do
      post admin_reply_message_thread_path(users(:one).id), params: { reply: "  " }
    end
  end

  test "destroy soft deletes and restore brings back" do
    msg = messages(:user_msg_read)
    delete admin_message_path(msg)
    assert_not_nil msg.reload.deleted_at
    patch restore_admin_message_path(msg)
    assert_nil msg.reload.deleted_at
  end

  test "unauthenticated user is redirected to sign in" do
    sign_out @admin
    get admin_messages_path
    assert_redirected_to new_user_session_path
  end
end
