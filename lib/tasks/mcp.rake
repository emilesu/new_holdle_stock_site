# T7 计费后台相关任务
# 使用: rails mcp:seed_plans       预填 5 档套餐（幂等）
# 使用: rails mcp:grant_member_keys 给历史付费会员批量发永久 AI key（D10）
namespace :mcp do
  desc "预填 5 档套餐（幂等，可重复执行）"
  task seed_plans: :environment do
    plans = [
      { plan_code: "welcome",          name: "新用户体验", price_cents: 0,    quota: 15,  is_member_upgrade: false },
      { plan_code: "starter",          name: "尝鲜包",     price_cents: 500,  quota: 20,  is_member_upgrade: false },
      { plan_code: "light",            name: "轻量包",     price_cents: 2000, quota: 90,  is_member_upgrade: false },
      { plan_code: "standard",         name: "标准包",     price_cents: 10000, quota: 500, is_member_upgrade: false },
      { plan_code: "member_permanent", name: "永久会员",   price_cents: 46800, quota: nil, is_member_upgrade: true }
    ]

    plans.each do |p|
      Plan.find_or_create_by!(plan_code: p[:plan_code]) { |r| r.assign_attributes(p) }
    end
    puts "已确认 #{Plan.count} 档套餐"
  end

  desc "给历史付费会员批量发永久 AI key（D10），已发过的不重复发"
  task grant_member_keys: :environment do
    member_plan = Plan.find_by!(plan_code: "member_permanent")

    users = User.where(role: :member)
    sent = 0
    skipped = 0

    users.find_each do |user|
      if user.api_keys.active.exists?(plan_code: "member_permanent")
        skipped += 1
        next
      end

      plain = ApiKey.generate!(user: user, plan: member_plan)
      if plain
        puts "用户 #{user.id}（#{user.nickname}）已发 key: #{plain}"
        sent += 1
      else
        puts "用户 #{user.id}（#{user.nickname}）已有 active key，跳过"
        skipped += 1
      end
    end

    puts "完成：新发 #{sent} 个，跳过 #{skipped} 个"
  end
end
