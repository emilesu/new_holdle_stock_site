require "test_helper"

class Admin::MessageBoardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two)
    sign_in @admin
  end

  test "index without show_deleted returns only normal messages" do
    get admin_message_boards_path
    assert_response :success

    assert_includes @response.body, message_boards(:normal_one).content
    assert_includes @response.body, message_boards(:normal_two).content
    assert_not_includes @response.body, message_boards(:deleted_one).content
    assert_not_includes @response.body, message_boards(:deleted_two).content
  end

  test "index with show_deleted=1 returns only deleted messages" do
    get admin_message_boards_path(show_deleted: 1)
    assert_response :success

    assert_includes @response.body, message_boards(:deleted_one).content
    assert_includes @response.body, message_boards(:deleted_two).content
    assert_not_includes @response.body, message_boards(:normal_one).content
    assert_not_includes @response.body, message_boards(:normal_two).content
  end

  test "index with show_deleted=1 shows deleted view badge" do
    get admin_message_boards_path(show_deleted: 1)
    assert_response :success
    assert_match "已删除留言视图", @response.body
  end

  test "index without show_deleted does not show deleted view badge" do
    get admin_message_boards_path
    assert_response :success
    assert_no_match "已删除留言视图", @response.body
  end

  test "unauthenticated user is redirected to sign in" do
    sign_out @admin
    get admin_message_boards_path
    assert_redirected_to new_user_session_path
  end
end