require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "plan_code 唯一" do
    Plan.create!(plan_code: "standard", name: "标准包", price_cents: 10_000, quota: 500)

    duplicate = Plan.new(plan_code: "standard", name: "重复", price_cents: 0, quota: 1)
    assert_not duplicate.valid?
    assert duplicate.errors[:plan_code].any?
  end

  test "unlimited? 对 quota=nil 返回 true" do
    plan = Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil)
    assert plan.unlimited?
  end
end
