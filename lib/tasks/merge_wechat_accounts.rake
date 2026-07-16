namespace :users do
  desc "遍历2026-07-14后新创建的微信访客账号，按昵称匹配旧账号。若旧账号为会员，则自动合并（旧账号继承WeChat凭据，删除新账号）"
  task merge_new_wechat_visitors: :environment do
    since_date = Date.new(2026, 7, 14)
    merged_count = 0
    skipped_not_member = 0
    skipped_multiple_matches = 0
    skipped_no_match = 0
    errors_list = []

    # 归一化微信头像 URL（与控制器中的逻辑一致）
    normalize_avatar = ->(url) {
      return nil if url.blank?
      url.sub(/\Ahttp:/i, "https:").sub(%r{/\d+\z}, "")
    }

    # 查找新创建的微信自动注册账号（访客、通过 WeChat OAuth 创建）
    new_accounts = User.where(role: "user")
                       .where("created_at >= ?", since_date.beginning_of_day)
                       .where("email LIKE ?", "wx_%@wechat-auto.local")
                       .order(:created_at)

    puts "=" * 80
    puts "微信访客账号合并修复 - #{Time.current}"
    puts "查找条件：created_at >= #{since_date}, role=user, email LIKE 'wx_%@wechat-auto.local'"
    puts "共找到 #{new_accounts.count} 个待检查的新账号"
    puts "=" * 80

    new_accounts.each do |new_acct|
      wx_nickname = new_acct.nickname
      if wx_nickname.blank? || wx_nickname.length < 2
        puts "  [跳过] 新账号 ##{new_acct.id} 昵称为空或过短: '#{wx_nickname}'"
        skipped_no_match += 1
        next
      end

      # 按昵称查找旧账号（与控制器启发式合并逻辑一致）
      old_candidates = User.where(weixin_unionid: nil)
                           .where.not(weixin_web_openid: nil)
                           .where(weixin_app_openid: nil)
                           .where("nickname = ? OR nickname LIKE ? ESCAPE '\\'",
                                  wx_nickname, "#{wx_nickname}\\_%")

      if old_candidates.count == 0
        puts "  [无匹配] 新账号 ##{new_acct.id} '#{wx_nickname}' → 无匹配旧账号"
        skipped_no_match += 1
        next
      end

      # 确定要合并的旧账号
      target_old = nil

      if old_candidates.count == 1
        target_old = old_candidates.first
      else
        # 多条匹配，尝试用头像做 tiebreaker
        norm_new_avatar = normalize_avatar.call(new_acct.avatar)
        if norm_new_avatar.present?
          avatar_match = old_candidates.select { |u| normalize_avatar.call(u.avatar) == norm_new_avatar }
          if avatar_match.size == 1
            target_old = avatar_match.first
            puts "  [头像决胜] 新账号 ##{new_acct.id} '#{wx_nickname}' → 多匹配中头像唯一命中旧账号 ##{target_old.id}"
          else
            puts "  [多匹配跳过] 新账号 ##{new_acct.id} '#{wx_nickname}' → #{old_candidates.count} 条匹配，头像无法唯一确定"
            skipped_multiple_matches += 1
            next
          end
        else
          puts "  [多匹配跳过] 新账号 ##{new_acct.id} '#{wx_nickname}' → #{old_candidates.count} 条匹配，无头像可做 tiebreaker"
          skipped_multiple_matches += 1
          next
        end
      end

      # 检查旧账号是否为会员
      unless target_old.is_member?
        puts "  [非会员跳过] 新账号 ##{new_acct.id} '#{wx_nickname}' → 旧账号 ##{target_old.id} '#{target_old.nickname}' 非会员(role=#{target_old.role})，跳过"
        skipped_not_member += 1
        next
      end

      # === 执行合并 ===
      begin
        ActiveRecord::Base.transaction do
          # 1. 收集要转移的 WeChat 凭据
          transfer_updates = {
            weixin_unionid: new_acct.weixin_unionid,
            weixin_web_openid: new_acct.weixin_web_openid,
            weixin_app_openid: new_acct.weixin_app_openid,
            avatar: new_acct.avatar
          }.compact  # 移除 nil 值，只更新实际有值的字段

          # 2. 先清除新账号的 WeChat 字段（释放唯一约束，避免与旧账号冲突）
          clear_fields = {}
          clear_fields[:weixin_unionid] = nil if new_acct.weixin_unionid.present?
          clear_fields[:weixin_web_openid] = nil if new_acct.weixin_web_openid.present?
          clear_fields[:weixin_app_openid] = nil if new_acct.weixin_app_openid.present?
          new_acct.update!(clear_fields) if clear_fields.any?

          # 3. 将凭据写入旧账号
          target_old.update!(transfer_updates)

          # 4. 记录旧账号的会员信息（日志用）
          member_info = if target_old.is_admin?
                          "管理员/永久会员"
                        else
                          "会员(到期日:#{target_old.member_expire_at&.to_date})"
                        end

          # 5. 删除新账号（级联删除关联的 favorites 等）
          new_acct.destroy!

          merged_count += 1
          puts "  ✅ [合并成功] 新账号 ##{new_acct.id} '#{wx_nickname}' → 旧账号 ##{target_old.id} '#{target_old.nickname}' (#{member_info})"
          puts "             写入: #{transfer_updates.keys.join(', ')}"
        end
      rescue => e
        errors_list << "新账号 ##{new_acct.id} '#{wx_nickname}' → 旧账号 ##{target_old.id}: #{e.message}"
        puts "  ❌ [合并失败] #{e.message}"
      end
    end

    puts ""
    puts "=" * 80
    puts "合并完成！"
    puts "  总处理新账号:       #{new_accounts.count}"
    puts "  合并成功(会员):     #{merged_count}"
    puts "  跳过(非会员):       #{skipped_not_member}"
    puts "  跳过(多匹配):       #{skipped_multiple_matches}"
    puts "  跳过(无匹配):       #{skipped_no_match}"
    puts "  异常失败:           #{errors_list.size}"
    if errors_list.any?
      puts ""
      puts "异常明细:"
      errors_list.each { |e| puts "  - #{e}" }
    end
    puts "=" * 80
  end
end
