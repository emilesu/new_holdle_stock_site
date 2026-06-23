require "test_helper"

class MessageBoardTest < ActiveSupport::TestCase
  test "normal scope returns only non-deleted messages" do
    results = MessageBoard.normal
    assert results.all? { |m| m.deleted_at.nil? }
    assert_includes results, message_boards(:normal_one)
    assert_includes results, message_boards(:normal_two)
    assert_not_includes results, message_boards(:deleted_one)
    assert_not_includes results, message_boards(:deleted_two)
  end

  test "deleted scope returns only soft-deleted messages" do
    results = MessageBoard.deleted
    assert results.all? { |m| m.deleted_at.present? }
    assert_includes results, message_boards(:deleted_one)
    assert_includes results, message_boards(:deleted_two)
    assert_not_includes results, message_boards(:normal_one)
    assert_not_includes results, message_boards(:normal_two)
  end

  test "soft_destroy sets deleted_at timestamp" do
    msg = message_boards(:normal_one)
    assert_nil msg.deleted_at
    msg.soft_destroy
    msg.reload
    assert_not_nil msg.deleted_at
  end

  test "restore clears deleted_at timestamp" do
    msg = message_boards(:deleted_one)
    assert_not_nil msg.deleted_at
    msg.restore
    msg.reload
    assert_nil msg.deleted_at
  end
end