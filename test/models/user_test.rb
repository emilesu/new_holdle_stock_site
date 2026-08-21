require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    Plan.create!(plan_code: "welcome", name: "新用户体验", price_cents: 0, quota: 15)
    Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil, is_member_upgrade: true)
  end

  test "注册普通用户自动发 welcome key（15 次）" do
    user = User.create!(email: "new_user@test.com", password: "password123", nickname: "新用户")

    key = user.api_keys.active.first
    assert key.present?, "注册后应有 active key"
    assert_equal "welcome", key.plan_code
    assert_equal 15, key.quota_remaining
  end

  test "注册会员用户自动发 member_permanent key（无限次）" do
    user = User.create!(email: "new_member@test.com", password: "password123", nickname: "新会员", role: :member)

    key = user.api_keys.active.first
    assert key.present?, "会员注册后应有 active key"
    assert_equal "member_permanent", key.plan_code
    assert_nil key.quota_remaining
  end

  test "注册发 key 幂等：已有 active key 不重复发" do
    user = User.create!(email: "dup_key@test.com", password: "password123", nickname: "重复用户")
    before_count = user.api_keys.active.count

    user.grant_initial_api_key

    assert_equal before_count, user.api_keys.active.count, "已有 active key 不应重复发放"
  end

  test "plans 未 seed 时注册不报错（降级容忍）" do
    Plan.destroy_all

    user = User.create!(email: "no_plan@test.com", password: "password123", nickname: "无套餐用户")

    assert user.persisted?
    assert_empty user.api_keys
  end
end
