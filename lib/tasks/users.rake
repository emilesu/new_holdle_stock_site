namespace :users do
  desc "从临时库old_user_temp关联users+identifies表迁移旧用户，提取微信Web端OpenID自动映射，兼容老用户微信登录自动回填UnionID"
  task import_old_data: :environment do
    # 时间脏数据兼容处理方法
    def safe_time(time_str)
      return nil if time_str.blank? || time_str.to_s.start_with?('0000-00-00')
      time_str
    end

    # 连接临时中转PostgreSQL数据库
    old_conn = PG.connect(dbname: 'old_user_temp')

    # 统计变量初始化
    total_rows = 0
    success_import = 0
    skip_dup_email = 0
    skip_dup_wx_openid = 0
    error_records = []

    # 关联用户表+第三方绑定表，只提取微信渠道的UID作为weixin_web_openid
    sql_join = <<~SQL
      SELECT
        u.*,
        i.uid AS weixin_web_openid
      FROM users u
      LEFT JOIN identifies i
        ON u.id = i.user_id AND i.provider = 'wechat'
      ORDER BY u.id ASC;
    SQL

    old_user_result = old_conn.exec(sql_join)

    old_user_result.each do |row|
      total_rows += 1

      # 每处理500条打印一次进度
      if total_rows % 500 == 0
        puts "==================== 迁移进度更新 ===================="
        puts "已处理总条数：#{total_rows}"
        puts "成功导入：#{success_import} | 邮箱重复跳过：#{skip_dup_email} | 微信ID重复跳过：#{skip_dup_wx_openid}"
        puts "======================================================"
      end

      # 基础字段清洗
      email = row['email']&.strip.presence
      wx_web_openid = row['weixin_web_openid']&.strip.presence

      # ========== 修复后的昵称处理逻辑 ==========
      raw_name = row['username']&.to_s.gsub(/\s+/, '')
      username = raw_name.truncate(30).presence
      username = "旧用户_#{row['id']}" if username.blank? || username.length < 3

      source_role = row['role']&.strip || 'nonmember'

      # 时间字段兼容处理
      member_expire_time = safe_time(row['end_time'])
      created_at = safe_time(row['created_at'])
      updated_at = safe_time(row['updated_at'])

      # 字符串字段截断
      avatar = row['avatar']&.strip&.truncate(250)
      motto = row['motto']&.strip&.truncate(250)

      # 旧角色映射新项目四级角色
      role_mapping = {
        'admin' => 'admin',
        'member' => 'member',
        'nonmember' => 'user'
      }
      target_role = role_mapping.fetch(source_role, 'user')

      # 双重唯一去重校验：邮箱 / 微信Web端OpenID 重复则跳过
      if email.present? && User.exists?(email: email)
        skip_dup_email += 1
        next
      end
      if wx_web_openid.present? && User.exists?(weixin_web_openid: wx_web_openid)
        skip_dup_wx_openid += 1
        next
      end

      # 生成随机安全密码，由Devise自动加密
      random_password = Devise.friendly_token[0, 20]

      begin
        User.create!(
          email: email || "#{wx_web_openid || "old_user_#{row['id']}"}@legacy-user.auto",
          password: random_password,
          nickname: username,
          role: target_role,
          member_expire_at: member_expire_time,

          # 微信三字段规则：仅填充旧网页OpenID，UnionID、APP端OpenID留空
          weixin_web_openid: wx_web_openid,
          weixin_unionid: nil,
          weixin_app_openid: nil,

          # 仅同步基础资料
          created_at: created_at,
          updated_at: updated_at,
          avatar: avatar
        )
        success_import += 1
      rescue StandardError => e
        error_msg = "【第#{total_rows}行失败】邮箱：#{email} | 微信OpenID：#{wx_web_openid} | 报错详情：#{e.message}"
        puts error_msg
        error_records << error_msg
      end
    end

    old_conn.close

    # 输出迁移完整统计日志
    puts "\n======================= 用户数据迁移执行汇总 ======================="
    puts "原始待迁移总条数：#{total_rows}"
    puts "成功导入新系统用户数：#{success_import}"
    puts "邮箱重复跳过条数：#{skip_dup_email}"
    puts "微信Web OpenID重复跳过条数：#{skip_dup_wx_openid}"
    puts "异常失败记录条数：#{error_records.size}"
    puts "=================================================================="

    if error_records.present?
      puts "\n【异常失败明细列表】"
      error_records.each { |err| puts err }
    else
      puts "\n✅ 所有数据迁移无异常！"
    end
  end
end