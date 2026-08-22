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

  desc "全库补发 key（幂等）：会员→无限次 / 非会员→welcome 15次，已有 active key 跳过"
  task ensure_all_user_keys: :environment do
    member_plan = Plan.find_by!(plan_code: "member_permanent")
    welcome_plan = Plan.find_by!(plan_code: "welcome")
    sent = 0
    skipped = 0
    failed = 0

    User.find_each do |user|
      if user.api_keys.active.exists?
        skipped += 1
        next
      end

      plan = user.is_member? ? member_plan : welcome_plan
      plain = ApiKey.generate!(user: user, plan: plan)
      if plain
        puts "用户 #{user.id}（#{user.nickname}）已发 #{plan.plan_code} key"
        sent += 1
      else
        skipped += 1
      end
    rescue => e
      failed += 1
      puts "用户 #{user.id} 发 key 失败: #{e.message}"
    end

    puts "完成：新发 #{sent} 个，跳过 #{skipped} 个，失败 #{failed} 个"
  end

  desc "全库重生成 key 明文（Phase3）：无明文或非 active 的 key 换新明文，active 且有明文跳过（幂等）"
  task backfill_key_plaintext: :environment do
    regenerated = 0
    skipped = 0
    failed = 0

    ApiKey.find_each do |key|
      # 已是新版（有明文）且在使用中的 key 不动，保证幂等
      if key.key_plaintext.present? && key.active?
        skipped += 1
        next
      end

      key.regenerate_plaintext!
      puts "key ##{key.id}（用户 #{key.user_id}，#{key.plan_code}）已换新明文"
      regenerated += 1
    rescue => e
      failed += 1
      puts "key ##{key.id} 重生成失败: #{e.message}"
    end

    puts "完成：重生成 #{regenerated} 个，跳过 #{skipped} 个，失败 #{failed} 个"
  end
end
