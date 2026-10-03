require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "normal scope returns only non-deleted messages" do
    results = Message.normal
    assert results.all? { |m| m.deleted_at.nil? }
    assert_includes results, messages(:user_msg_read)
    assert_includes results, messages(:admin_msg_unread)
    assert_not_includes results, messages(:deleted_msg)
  end

  test "deleted scope returns only soft-deleted messages" do
    results = Message.deleted
    assert results.all? { |m| m.deleted_at.present? }
    assert_includes results, messages(:deleted_msg)
    assert_not_includes results, messages(:user_msg_read)
  end

  test "unread_for_admin only counts unread user messages" do
    results = Message.unread_for_admin
    assert_includes results, messages(:user_msg_unread)
    assert_not_includes results, messages(:user_msg_read)
    assert_not_includes results, messages(:admin_msg_unread) # 站长自己发的不计
    assert_not_includes results, messages(:deleted_msg)      # 已隐藏的不计
  end

  test "unread_for_user only counts unread admin messages" do
    results = Message.unread_for_user
    assert_includes results, messages(:admin_msg_unread)
    assert_not_includes results, messages(:user_msg_unread)
  end

  test "soft_destroy sets deleted_at timestamp" do
    msg = messages(:user_msg_read)
    assert_nil msg.deleted_at
    msg.soft_destroy
    msg.reload
    assert_not_nil msg.deleted_at
  end

  test "restore clears deleted_at timestamp" do
    msg = messages(:deleted_msg)
    assert_not_nil msg.deleted_at
    msg.restore
    msg.reload
    assert_nil msg.deleted_at
  end

  test "sender defaults to user and admin can be set" do
    msg = users(:one).messages.new(content: "测试")
    assert_equal "user", msg.sender
    msg.sender = "admin"
    assert_equal "admin", msg.sender
  end

  test "has_sensitive? blocks listed words and passes clean text" do
    assert Message.has_sensitive?("我想咨询赌博相关问题")
    assert Message.has_sensitive?("加微信详聊")
    assert_not Message.has_sensitive?("金字塔策略的现金流权重怎么算")
    assert_not Message.has_sensitive?(nil)
  end
end
