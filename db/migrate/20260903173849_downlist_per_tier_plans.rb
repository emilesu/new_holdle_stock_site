class DownlistPerTierPlans < ActiveRecord::Migration[7.1]
  # 定价改版：停售按次三档（保留记录，只停新售卖；存量 api_keys 不受影响，继续扣次）
  # plans 为后台手工维护的存量数据，迁移前先断言五档齐全，避免静默 0 行更新导致"以为下架实则未下架"
  UP_CODES = %w[starter light standard]
  KEEP_CODES = %w[welcome member_permanent]

  def up
    required = UP_CODES + KEEP_CODES
    existing = Plan.where(plan_code: required).pluck(:plan_code)
    missing = required - existing
    raise "plans 定价数据缺失（请先在后台/手动入库）：#{missing.join(', ')}" if missing.any?

    count = Plan.where(plan_code: UP_CODES).update_all(active: false)
    raise "预期停售 #{UP_CODES.size} 档按次套餐，实际更新 #{count} 行" unless count == UP_CODES.size

    # 确保在售两档开启（免费体验 + HOLDLE会员）
    Plan.where(plan_code: KEEP_CODES).update_all(active: true)
    # 468 卡名去掉「永久」主打 → 价值引向「进阶实战 + AI 无限次」
    # 注意：plan.name 同时作为 order.title / 支付 subject，改名会同步到支付描述
    Plan.where(plan_code: "member_permanent").update_all(name: "HOLDLE会员")
  end

  def down
    Plan.where(plan_code: UP_CODES).update_all(active: true)
    Plan.where(plan_code: "member_permanent").update_all(active: true)
    # 还原原名（原有语义即为「永久会员」）；如已被人为改名，回滚后需人工校正
    Plan.where(plan_code: "member_permanent").update_all(name: "永久会员")
  end
end