module Admin
  # AI 提问分析报表：只读，统计 usage_logs 中 confirmed 的提问（数据源见 00_提问分析报表需求_Trae版.md）
  class UsageAnalyticsController < BaseController
    CATEGORIES = {
      "状态A/择时"    => %w[状态A 开窗 月K 择时 买入时机 突破],
      "选股/企业分析" => %w[选股 ROE 企业分析 行业 财报 估值],
      "交易管理/止损" => %w[止损 仓位 分散 出场 周K 持有],
      "复盘/个股"     => %w[复盘 回测 个股],
      "方法论/理念"   => %w[方法论 概率 长期 理念 体系]
    }.freeze

    def index
      @days = [7, 30].include?(params[:days].to_i) ? params[:days].to_i : 7
      @logs = confirmed_logs

      # 总览卡片
      @total_questions = @logs.count
      @active_users = @logs.select(:user_id).distinct.count
      @today_questions = confirmed_logs.where(created_at: Date.current.all_day).count
      @avg_per_user = @active_users.zero? ? 0 : (@total_questions.to_f / @active_users).round(1)

      # 分类统计（一条可命中多类，都计；都不中归其他）
      @category_counts = category_counts(@logs)

      # Top 20 问题（按内容分组计数）
      @top_questions = @logs.where.not(question: [nil, ""]).group(:question).count
                              .sort_by { |_, count| -count }.first(20)

      # 最近 20 条原始问题
      @recent_questions = @logs.where.not(question: [nil, ""]).includes(:user)
                               .order(created_at: :desc).limit(20)

      # Top 10 活跃用户（一次查用户，避免视图 N+1）
      user_counts = @logs.group(:user_id).count.sort_by { |_, count| -count }.first(10).to_h
      users = User.where(id: user_counts.keys).index_by(&:id)
      @top_users = user_counts.map { |user_id, count| [users[user_id], count] }
                             .reject { |user, _| user.nil? }
    end

    private

    def confirmed_logs
      UsageLog.where(status: "confirmed")
              .where(created_at: @days.days.ago.beginning_of_day..Time.current)
    end

    def category_counts(logs)
      counts = CATEGORIES.transform_values { |_| 0 }
      counts["其他/闲聊"] = 0
      logs.each do |log|
        text = log.question.to_s
        next if text.blank?

        hit = false
        CATEGORIES.each do |name, keywords|
          next unless keywords.any? { |kw| text.include?(kw) }

          counts[name] += 1
          hit = true
        end
        counts["其他/闲聊"] += 1 unless hit
      end
      counts
    end
  end
end
