namespace :dev do
  namespace :users do
    desc "创建测试用户"
    task create: :environment do
      create_users
    end

    desc "重置所有测试用户"
    task reset: :environment do
      puts "删除所有用户..."
      User.destroy_all
      puts "用户已删除"
      create_users
    end

    desc "创建普通用户"
    task normal: :environment do
      user = User.find_or_initialize_by(email: 'user@example.com')
      if user.new_record?
        user.nickname = '普通用户'
        user.password = '123456'
        user.role = 'user'
        user.save!
        puts "普通用户创建成功: user@example.com / 123456"
      else
        puts "普通用户已存在: user@example.com"
      end
    end

    desc "创建会员用户"
    task member: :environment do
      user = User.find_or_initialize_by(email: 'member@example.com')
      if user.new_record?
        user.nickname = '会员用户'
        user.password = '123456'
        user.role = 'member'
        user.member_expire_at = 1.year.from_now
        user.save!
        puts "会员用户创建成功: member@example.com / 123456"
      else
        puts "会员用户已存在: member@example.com"
      end
    end

    desc "创建管理员"
    task admin: :environment do
      user = User.find_or_initialize_by(email: 'admin@example.com')
      if user.new_record?
        user.nickname = '管理员'
        user.password = '123456'
        user.role = 'admin'
        user.save!
        puts "管理员创建成功: admin@example.com / 123456"
      else
        puts "管理员已存在: admin@example.com"
      end
    end

    desc "创建超级管理员"
    task super_admin: :environment do
      user = User.find_or_initialize_by(email: 'super@example.com')
      if user.new_record?
        user.nickname = '超级管理员'
        user.password = '123456'
        user.role = 'super_admin'
        user.save!
        puts "超级管理员创建成功: super@example.com / 123456"
      else
        puts "超级管理员已存在: super@example.com"
      end
    end
  end
end

def create_users
  puts "开始创建测试用户..."
  
  # 创建普通用户
  user = User.find_or_initialize_by(email: 'user@example.com')
  if user.new_record?
    user.nickname = '普通用户'
    user.password = '123456'
    user.role = 'user'
    user.save!
    puts "✓ 普通用户: user@example.com / 123456"
  else
    puts "✓ 普通用户已存在"
  end

  # 创建会员用户
  member = User.find_or_initialize_by(email: 'member@example.com')
  if member.new_record?
    member.nickname = '会员用户'
    member.password = '123456'
    member.role = 'member'
    member.member_expire_at = 1.year.from_now
    member.save!
    puts "✓ 会员用户: member@example.com / 123456"
  else
    puts "✓ 会员用户已存在"
  end

  # 创建管理员
  admin = User.find_or_initialize_by(email: 'admin@example.com')
  if admin.new_record?
    admin.nickname = '管理员'
    admin.password = '123456'
    admin.role = 'admin'
    admin.save!
    puts "✓ 管理员: admin@example.com / 123456"
  else
    puts "✓ 管理员已存在"
  end

  # 创建超级管理员
  super_admin = User.find_or_initialize_by(email: 'super@example.com')
  if super_admin.new_record?
    super_admin.nickname = '超级管理员'
    super_admin.password = '123456'
    super_admin.role = 'super_admin'
    super_admin.save!
    puts "✓ 超级管理员: super@example.com / 123456"
  else
    puts "✓ 超级管理员已存在"
  end

  puts "\n所有测试用户创建完成！"
  puts "\n测试用户列表:"
  User.all.each do |u|
    puts "  - #{u.email} (#{u.nickname}) - #{u.role}"
  end
end
