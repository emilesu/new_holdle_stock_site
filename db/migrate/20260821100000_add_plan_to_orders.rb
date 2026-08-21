# T7 Phase2：orders 表加 plan_code/quota（多 SKU 计费）
class AddPlanToOrders < ActiveRecord::Migration[7.1]
  def change
    # 历史订单均为 member_permanent，默认值保持兼容
    add_column :orders, :plan_code, :string, default: "member_permanent", null: false, comment: "购买套餐编码"
    add_column :orders, :quota, :integer, comment: "本次购买次数（member_permanent=nil 表示无限）"
  end
end
