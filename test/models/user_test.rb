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

  test "角色从 user 升级为 member 时自动升级 key 为永久会员" do
    user = User.create!(email: "upgrade@test.com", password: "password123", nickname: "待升级用户")
    key = user.api_keys.active.first
    assert_equal "welcome", key.plan_code, "初始应为 welcome 套餐"
    assert_equal 15, key.quota_remaining

    user.update!(role: :member)

    key.reload
    assert_equal "member_permanent", key.plan_code, "升级后应为 member_permanent 套餐"
    assert_nil key.quota_remaining, "升级后应为无限次"
  end

  test "角色已经是 member 时不重复触发升级" do
    user = User.create!(email: "already_member@test.com", password: "password123", nickname: "已会员", role: :member)
    key = user.api_keys.active.first
    assert_equal "member_permanent", key.plan_code

    # 更新其他字段不应触发升级回调
    user.update!(nickname: "新昵称")
    key.reload
    assert_equal "member_permanent", key.plan_code
  end

  test "已有 member_permanent key 的用户升级角色不报错" do
    user = User.create!(email: "premium@test.com", password: "password123", nickname: "高级用户")
    key = user.api_keys.active.first
    key.convert_to_member! # 手动升级 key

    user.update!(role: :member)

    key.reload
    assert_equal "member_permanent", key.plan_code
    assert_nil key.quota_remaining
  end

  test "角色从 member 降级为 user 时自动降级 key 为欢迎套餐" do
    user = User.create!(email: "downgrade@test.com", password: "password123", nickname: "待降级用户", role: :member)
    key = user.api_keys.active.first
    assert_equal "member_permanent", key.plan_code
    assert_nil key.quota_remaining

    user.update!(role: :user)

    key.reload
    assert_equal "welcome", key.plan_code, "降级后应为 welcome 套餐"
    assert_equal 15, key.quota_remaining, "降级后应为 15 次"
  end

  test "角色已经是 user 时不重复触发降级" do
    user = User.create!(email: "already_user@test.com", password: "password123", nickname: "已是访客")
    key = user.api_keys.active.first
    assert_equal "welcome", key.plan_code

    # 更新其他字段不应触发降级回调
    user.update!(nickname: "新昵称")
    key.reload
    assert_equal "welcome", key.plan_code
    assert_equal 15, key.quota_remaining
  end

  test "已有 welcome key 的用户降级角色不报错" do
    user = User.create!(email: "already_welcome@test.com", password: "password123", nickname: "已是欢迎用户", role: :member)
    key = user.api_keys.active.first
    key.update!(plan_code: "welcome", quota_remaining: 15, quota_total: 15) # 手动降级 key

    user.update!(role: :user)

    key.reload
    assert_equal "welcome", key.plan_code
    assert_equal 15, key.quota_remaining
  end
end
