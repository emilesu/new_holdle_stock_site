require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @plan = Plan.create!(plan_code: "standard", name: "标准包", price_cents: 10_000, quota: 500)
  end

  test "generate! 返回明文且库存 SHA256 哈希" do
    plain = ApiKey.generate!(user: @user, plan: @plan)

    assert_match(/\Ahl_[0-9a-f]{16}\z/, plain)
    key = ApiKey.last
    assert_equal Digest::SHA256.hexdigest(plain), key.key_hash
    assert_equal plain[0, 11], key.key_prefix
    assert_equal 500, key.quota_remaining
    assert_equal 500, key.quota_total
    assert_equal "standard", key.plan_code
    assert key.active?
  end

  test "generate! 已有 active key 时不重复生成" do
    ApiKey.generate!(user: @user, plan: @plan)

    assert_nil ApiKey.generate!(user: @user, plan: @plan)
    assert_equal 1, @user.api_keys.active.count
  end

  test "unlimited? 对 member_permanent（quota_remaining=nil）返回 true" do
    member_plan = Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil)
    key = ApiKey.generate!(user: users(:two), plan: member_plan) && ApiKey.last

    assert key.unlimited?
  end

  test "decrement_quota! 扣减并在 0 处兜底" do
    key = ApiKey.generate!(user: @user, plan: @plan) && ApiKey.last

    key.update!(quota_remaining: 1)
    key.decrement_quota!
    assert_equal 0, key.quota_remaining

    key.decrement_quota!
    assert_equal 0, key.quota_remaining
  end

  test "decrement_quota! 对无限次 key 不扣减" do
    member_plan = Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil)
    key = ApiKey.generate!(user: users(:two), plan: member_plan) && ApiKey.last

    assert_nil key.quota_remaining
    key.decrement_quota!
    assert_nil key.quota_remaining
  end
end
