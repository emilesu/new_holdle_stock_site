class AddStudentPlans < ActiveRecord::Migration[7.1]
  # 新增两档套餐：
  #   student_course        268 元课程学员（永久）：金字塔完整 + 学员档课程/文章，AI 仍 15 次
  #   member_from_student   200 元学员补差价升会员（仅 role=student 可购，orders_controller 校验）
  # plans 无后台维护入口，走迁移入库（与 DownlistPerTierPlans 手工数据迁移同思路）
  def up
    add_column :plans, :is_student_upgrade, :boolean, default: false, comment: "是否学员单（268 档=true，履约时 role 置 student）"

    Plan.create!(
      plan_code: "student_course",
      name: "HOLDLE课程学员",
      price_cents: 26800,
      quota: 15, # 仅展示用（学员不改变 Key 次数）；履约走 is_student_upgrade 分支
      is_member_upgrade: false,
      is_student_upgrade: true,
      active: true
    )

    Plan.create!(
      plan_code: "member_from_student",
      name: "HOLDLE会员（学员补差价）",
      price_cents: 20000,
      quota: nil, # 无限次（is_member_upgrade 履约时同 member_permanent）
      is_member_upgrade: true,
      is_student_upgrade: false,
      active: true
    )
  end

  def down
    Plan.where(plan_code: %w[student_course member_from_student]).delete_all
    remove_column :plans, :is_student_upgrade, :boolean
  end
end
