class RenameHoldlePlanNames < ActiveRecord::Migration[7.1]
  # 套餐名统一为「HOLDLE-xxx」命名风格（join/plans 卡片标题直接取 plan.name）
  # 注意：plan.name 同时作为 order.title / 支付 subject，新订单支付描述随之变化，历史订单已存 title 不受影响
  NAMES = {
    "student_course"      => "HOLDLE-课程学员",
    "member_permanent"    => "HOLDLE-会员",
    "member_from_student" => "HOLDLE-会员（学员补差价）"
  }.freeze

  OLD_NAMES = {
    "student_course"      => "HOLDLE课程学员",
    "member_permanent"    => "HOLDLE会员",
    "member_from_student" => "HOLDLE会员（学员补差价）"
  }.freeze

  def up
    NAMES.each { |code, name| Plan.where(plan_code: code).update_all(name: name) }
  end

  def down
    OLD_NAMES.each { |code, name| Plan.where(plan_code: code).update_all(name: name) }
  end
end
