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
      # 计数口径数据源：confirmed + merged 都算活动（merged 是 90s 合并的同回合补充检索），
      # 按 round_id 去重计提问；分类/高频词/最近问题仍用 @logs（confirmed，防 merged 重复计入）
      @count_logs = count_logs

      # 总览卡片（提问数按 round_id 去重：一回合 1 confirmed + N merged 计 1 次；老数据 round_id 为空回退 request_id 每条计 1）
      @total_questions = @count_logs.distinct.count("COALESCE(round_id, request_id)")
      # 活跃用户与人均须与总提问同口径（count_logs：confirmed+merged），
      # 否则跨窗口场景（同 round 仅 merged 在窗内）用户出现在 Top 10 却不算活跃用户
      @active_users = @count_logs.select(:user_id).distinct.count
      @today_questions = count_logs.where(created_at: Date.current.all_day).distinct.count("COALESCE(round_id, request_id)")
      @avg_per_user = @active_users.zero? ? 0 : (@total_questions.to_f / @active_users).round(1)

      # 回填映射：precheck 未传 question 的 confirmed（新 agent 每轮首请求）用同 round 最早一条
      # 带 question 的 merged 补文本（原始首问更贴切）；分类/高频/最近提问共用，仍只统计 confirmed
      @question_fallback = question_fallback(@logs)

      # 分类统计（一条可命中多类，都计；都不中归其他）
      @category_counts = category_counts(@logs)

      # Top 20 问题（按回填后的问题原文分组计数）
      @top_questions = top_questions(@logs)

      # 最近 20 条原始问题（已带 question 的 + 缺 question 但可回填的，合并按时间倒序取前 20）
      @recent_questions = recent_questions(@logs)

      # Top 10 活跃用户（按去重后提问数排序，一次查用户避免视图 N+1）
      # 注意：不能用 group(:user_id).count（返回 COUNT(*) 行数），须 select 自定义去重聚合列
      user_counts = @count_logs.group(:user_id)
                               .select("user_id, COUNT(DISTINCT COALESCE(round_id, request_id)) AS question_count")
                               .order(Arel.sql("COUNT(DISTINCT COALESCE(round_id, request_id)) DESC"))
                               .limit(10)
                               .map { |row| [row.user_id, row.question_count.to_i] }.to_h
      users = User.where(id: user_counts.keys).index_by(&:id)
      @top_users = user_counts.map { |user_id, count| [users[user_id], count] }
                             .reject { |user, _| user.nil? }
    end

    private

    def confirmed_logs
      UsageLog.where(status: "confirmed")
              .where(created_at: @days.days.ago.beginning_of_day..Time.current)
    end

    def count_logs
      UsageLog.where(status: %w[confirmed merged])
              .where(created_at: @days.days.ago.beginning_of_day..Time.current)
    end

    # 缺 question 的 confirmed → 同 round 最早一条带 question 的 merged 文本（升序取首条 ≈ 原始首问）
    def question_fallback(logs)
      round_ids = logs.filter_map { |l| l.round_id if l.question.blank? && l.round_id.present? }.uniq
      return {} if round_ids.empty?

      UsageLog.where(status: "merged", round_id: round_ids)
              .where.not(question: [nil, ""])
              .order(created_at: :asc)
              .pluck(:round_id, :question)
              .group_by(&:first)
              .transform_values { |pairs| pairs.first.last }
    end

    # confirmed 记录的有效问题文本：precheck 落库值优先，缺失时用同 round 回填值
    def effective_question(log)
      log.question.presence || @question_fallback[log.round_id]
    end

    def category_counts(logs)
      counts = CATEGORIES.transform_values { |_| 0 }
      counts["其他/闲聊"] = 0
      logs.each do |log|
        text = effective_question(log)
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

    # Top 20 问题（Ruby 侧按回填后的问题原文分组，复用回填文本）
    def top_questions(logs)
      counts = Hash.new(0)
      logs.each do |log|
        text = effective_question(log)
        counts[text] += 1 unless text.blank?
      end
      counts.sort_by { |_, count| -count }.first(20)
    end

    # 最近 20 条原始问题：两段取数（已带 question 的直接取；缺 question 的可回填后取），
    # 合并按时间倒序取前 20，保证列表优先展示真实问题、不受空 question 记录挤压
    def recent_questions(logs)
      with_q = logs.where.not(question: [nil, ""]).includes(:user).order(created_at: :desc).limit(20).to_a
      blank = logs.where(question: [nil, ""]).where.not(round_id: nil)
                  .includes(:user).order(created_at: :desc).limit(100).to_a
      blank.each do |log|
        log.question = @question_fallback[log.round_id] if @question_fallback[log.round_id]
      end
      (with_q + blank.select { |l| l.question.present? })
        .sort_by { |l| -l.created_at.to_i }
        .first(20)
    end
  end
end
