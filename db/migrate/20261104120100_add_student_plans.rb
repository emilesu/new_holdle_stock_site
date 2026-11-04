class AddStudentPlans < ActiveRecord::Migration[7.1]
  # 新增两档套餐：
  #   student_course        268 元课程学员（永久）：金字塔完整 + 学员档课程/文章，AI 仍 15 次
  #   member_from_student   200 元学员补差价升会员（仅 role=student 可购，orders_controller 校验）
  # plans 无后台维护入口，走迁移入库（与 DownlistPerTierPlans 手工数据迁移同思路）
  def up
    add_column :plans, :is_student_upgrade, :boolean, default: false, comment: "是否学员单（268 档=true，履约时 role 置 student）"

    # find_or_create_by：plans 为后台手工维护的存量数据（见 DownlistPerTierPlans 注释），
    # 若生产已被人工预插同码行，create! 会因 uniqueness 校验抛异常中断部署
    Plan.find_or_create_by!(plan_code: "student_course") do |p|
      p.name = "HOLDLE课程学员"
      p.price_cents = 26800
      p.quota = 15 # 仅展示用（学员不改变 Key 次数）；履约走 is_student_upgrade 分支
      p.is_member_upgrade = false
      p.is_student_upgrade = true
      p.active = true
    end

    Plan.find_or_create_by!(plan_code: "member_from_student") do |p|
      p.name = "HOLDLE会员（学员补差价）"
      p.price_cents = 20000
      p.quota = nil # 无限次（is_member_upgrade 履约时同 member_permanent）
      p.is_member_upgrade = true
      p.is_student_upgrade = false
      p.active = true
    end
  end

  def down
    Plan.where(plan_code: %w[student_course member_from_student]).delete_all
    remove_column :plans, :is_student_upgrade, :boolean
  end
end
