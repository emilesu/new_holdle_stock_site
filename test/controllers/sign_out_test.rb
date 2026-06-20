require "test_helper"

class SignOutTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
  end

  test "sign out via DELETE succeeds and redirects to root" do
    sign_in @user
    get root_url
    assert_response :success

    delete destroy_user_session_path
    assert_redirected_to root_path

    follow_redirect!
    assert_response :success
  end

  test "sign out via GET returns 404" do
    sign_in @user
    get destroy_user_session_path
    assert_response :not_found
  end

  test "unauthenticated user cannot access protected page and can sign in then out" do
    original_url = "/courses"
    get original_url
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success

    post user_session_path, params: {
      user: { email: @user.email, password: "password123" }
    }
    assert_redirected_to original_url

    follow_redirect!
    assert_response :success

    delete destroy_user_session_path
    assert_redirected_to root_path
  end

  test "sign out clears session" do
    sign_in @user
    delete destroy_user_session_path

    get root_path
    assert_response :success
    assert_select "a[href='#{new_user_session_path}']"
  end

  test "signed out user cannot access protected page" do
    sign_in @user
    delete destroy_user_session_path

    get "/courses"
    assert_redirected_to new_user_session_path
  end
end