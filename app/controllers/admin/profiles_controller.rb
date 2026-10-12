module Admin
  class ProfilesController < BaseController
    # 企业质量档案人工闸门：待审队列 → 预览（与前台同 sanitize 管道）→ 发布/撤回/回滚
    before_action :load_profile, only: [:show, :publish, :withdraw, :rollback]

    def index
      @profiles = QualityProfile.includes(:stock).order(updated_at: :desc).limit(200)
      @profiles = @profiles.where(status: params[:status]) if params[:status].in?(QualityProfile::STATUSES)
    end

    def show
      @versions = @profile.versions
      # 预览走与前台完全相同的 render_safe 管道（所见即所得）
      @preview_html = MarkdownRenderer.render_safe(@profile.markdown)
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

    private

    def load_profile
      @profile = QualityProfile.find(params[:id])
    end
  end
end
