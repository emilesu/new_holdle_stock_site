module Admin
  class ProfilesController < BaseController
    # 企业质量档案人工闸门：待审队列 → 预览（与前台同 sanitize 管道）→ 发布/撤回/回滚/手动编辑/批量处理
    before_action :load_profile, only: [:show, :edit, :update, :publish, :withdraw, :rollback]

    MARKET_LABELS = { "CN" => "A股", "HK" => "港股", "US" => "美股" }.freeze
    TIME_RANGES = { "7d" => "最近 7 天", "30d" => "最近 30 天", "90d" => "最近 90 天" }.freeze
    BULK_PUBLISH_LIMIT = 20 # 批量发布单批上限（信任模型要求逐条确认，不做大水漫灌）

    def index
      @q = params[:q].to_s.strip
      @market = params[:market].to_s
      @range = params[:range].to_s

      scope = QualityProfile.includes(:stock).references(:stock)
      scope = scope.where(status: params[:status]) if params[:status].in?(QualityProfile::STATUSES)
      scope = scope.where(stocks: { market: @market }) if @market.in?(MARKET_LABELS.keys)
      if (days = @range[/\A(\d+)d\z/, 1])
        scope = scope.where("quality_profiles.updated_at >= ?", days.to_i.days.ago)
      end

      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        conds = ["stocks.name ILIKE :q OR stocks.symbol ILIKE :q OR quality_profiles.title ILIKE :q OR quality_profiles.period LIKE :q"]
        binds = { q: like }
        # 代码归一化：后缀式（603259.SH）/前缀式（sh603259）大小写不敏感，与发布 API 同规则
        if (norm = normalized_symbol(@q))
          conds << "stocks.symbol = :sym"
          binds[:sym] = norm
        end
        scope = scope.where(conds.join(" OR "), **binds)
      end

      @profiles = scope.order(updated_at: :desc).page(params[:page]).per(50)
    end

    def show
      @versions = @profile.versions
      # 预览走与前台完全相同的 render_profile 管道（剥离首 H1 + 锚点注入，所见即所得）
      @preview_html, = MarkdownRenderer.render_profile(@profile.markdown)
    end

    def edit
      return if @profile.status.in?(QualityProfile::EDITABLE_STATUSES)

      redirect_to admin_profile_path(@profile), alert: "「#{@profile.status_label}」状态不支持编辑"
    end

    def update
      unless @profile.status.in?(QualityProfile::EDITABLE_STATUSES)
        return redirect_to admin_profile_path(@profile), alert: "「#{@profile.status_label}」状态不支持编辑"
      end

      @draft_title = params.dig(:profile, :title).to_s
      @draft_markdown = params.dig(:profile, :markdown).to_s

      if params[:preview].present?
        # 仅渲染预览、不落库（与前台同管道，所见即所得）
        @preview_html, = MarkdownRenderer.render_profile(@draft_markdown)
        return render :edit
      end

      @profile.manual_edit!(title: @draft_title, markdown: @draft_markdown, user: current_user)
      redirect_to admin_profile_path(@profile),
                  notice: "已保存为新版本 v#{@profile.current_version_no}，发布后对外生效"
    rescue => e
      flash.now[:alert] = "保存失败：#{e.message}"
      render :edit, status: :unprocessable_entity
    end

    def publish
      @profile.publish!(current_user)
      redirect_to admin_profile_path(@profile), notice: "已发布，同股票旧期次已自动转「已被取代」"
    rescue => e
      redirect_to admin_profile_path(@profile), alert: "发布失败：#{e.message}"
    end

    def withdraw
      @profile.withdraw!
      redirect_to admin_profile_path(@profile), notice: "已撤回，前台立即下架（数据保留）"
    end

    def rollback
      @profile.rollback_to!(params[:version_no].to_i, current_user)
      redirect_to admin_profile_path(@profile), notice: "已回滚到 v#{params[:version_no]} 并直接发布（人工闸门行为）"
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_profile_path(@profile), alert: "目标版本不存在"
    end

    # 批量发布确认页：逐条列出摘要，人工闸门不因批量而放松
    def bulk_review
      @profiles = QualityProfile.includes(:stock).where(id: bulk_ids).order(:updated_at, :id)
      if @profiles.empty?
        redirect_to admin_profiles_path, alert: "未选择任何档案"
      else
        @eligible = @profiles.select { |p| p.status == "pending_review" && p.meta["gate_passed"] == true }
        @excluded = @profiles - @eligible
        if @eligible.size > BULK_PUBLISH_LIMIT
          redirect_to admin_profiles_path, alert: "符合发布条件的档案超过单批上限 #{BULK_PUBLISH_LIMIT} 条，请缩小范围"
        end
      end
    end

    # 批量执行：每条独立事务，单条失败不影响其余，逐条报告结果
    def bulk_apply
      return redirect_to(admin_profiles_path, alert: "未选择任何档案") if bulk_ids.empty?

      action = params[:bulk_action].to_s
      return redirect_to(admin_profiles_path, alert: "未知批量操作") unless action.in?(%w[publish withdraw])

      profiles = QualityProfile.includes(:stock).where(id: bulk_ids).order(:updated_at, :id)

      if action == "publish"
        publishable = profiles.count { |p| p.status == "pending_review" && p.meta["gate_passed"] == true }
        if publishable > BULK_PUBLISH_LIMIT
          return redirect_to admin_profiles_path, alert: "符合发布条件的档案超过单批上限 #{BULK_PUBLISH_LIMIT} 条"
        end
      end

      succeeded = []
      failed = []
      profiles.each do |p|
        begin
          case action
          when "publish"
            raise "非待审状态（当前为#{p.status_label}）" unless p.status == "pending_review"

            p.publish!(current_user)
          when "withdraw"
            raise "当前状态无需/不可撤回（#{p.status_label}）" if p.status == "withdrawn"

            p.withdraw!
          end
          succeeded << p
        rescue => e
          failed << "#{p.stock.name}（#{p.period}）：#{e.message}"
        end
      end

      label = action == "publish" ? "发布" : "撤回"
      msg = "批量#{label}完成：成功 #{succeeded.size} 条"
      msg += "，失败 #{failed.size} 条（#{failed.join('；')}）" if failed.any?
      redirect_to admin_profiles_path, notice: msg
    end

    private

    def load_profile
      @profile = QualityProfile.find(params[:id])
    end

    def bulk_ids
      params[:ids].to_a.map { |i| i.to_s.strip }.reject(&:empty?).map(&:to_i).uniq
    end

    # 603259.SH / sh603259 → SH603259；裸 6 位代码交给 ILIKE 模糊匹配即可
    def normalized_symbol(raw)
      if (m = raw.match(/\A(\d{6})\.(SH|SZ|BJ)\z/i))
        "#{m[2].upcase}#{m[1]}"
      elsif (m = raw.match(/\A(SH|SZ|BJ)(\d{6})\z/i))
        "#{m[1].upcase}#{m[2]}"
      end
    end
  end
end
