class DownlistPerTierPlans < ActiveRecord::Migration[7.1]
  def up
    # 定价改版：停售按次三档（保留记录，只停新售卖；存量 api_keys 不受影响，继续扣次）
    Plan.where(plan_code: %w[starter light standard]).update_all(active: false)
    # 确保在售两档开启（免费体验 + HOLDLE会员）
    Plan.where(plan_code: %w[welcome member_permanent]).update_all(active: true)
    # 468 卡名去掉「永久」主打 → 价值引向「进阶实战 + AI 无限次」
    # 注意：plan.name 同时作为 order.title / 支付 subject，改名会同步到支付描述
    Plan.where(plan_code: "member_permanent").update_all(name: "HOLDLE会员")
  end

  def down
    Plan.where(plan_code: %w[starter light standard]).update_all(active: true)
    Plan.where(plan_code: "member_permanent").update_all(name: "永久会员")
  end
end