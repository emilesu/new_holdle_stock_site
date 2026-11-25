# 月K开窗观察（需求单 v0.3.0）：快照只供技术判定，页面零判定计算、零绝对数值渲染
# 财务维度（预设筛选/ROE/金融/ST）由 Trae 财务库 join（契约 v0.4.0 §三.1），快照不携带
# 访问控制：正式形态=会员完整视图 + 非会员 teaser；当前暗发布=DARK_RELEASE 仅管理员
class WindowWatchController < ApplicationController
  # 暗发布开关（2026-11-24 站长定）：true=仅管理员可访问（导航入口同步隐藏，其余用户重定向首页不留痕迹）
  # 调试完成后置 false，即恢复需求单 §一 的正式访问控制：会员完整视图 + 非会员 teaser
  DARK_RELEASE = true

  # 全量视图排序白名单（R3/A6：禁止参数直接透传 SQL）
  SORT_ORDERS = {
    "ratio_asc" => "ratio ASC", "ratio_desc" => "ratio DESC",
    "open_month_desc" => "open_month DESC NULLS LAST",
    "sa_run_desc" => "sa_run DESC"
  }.freeze
  PAGE_PER = 100

  def index
    if DARK_RELEASE && !(user_signed_in? && current_user.is_admin?)
      redirect_to root_path and return
    end
    @snapshot = WindowWatchSnapshot.latest
    @is_member = user_signed_in? && current_user.content_tier >= User::TIER_MEMBER
    return unless @snapshot && @is_member

    # R1：视图开关只切 main/all，筛选条件随视图重置（行为一致）
    @view = params[:view] == "all" ? "all" : "main"
    if @view == "main"
      # 财务预设视图：命中集来自财务库（近3财年 ROE≥档位 且 经营现金流>0，最新披露口径）
      @band = WindowWatch::FinancialPreset.band_for(params[:band])
      hit_codes = WindowWatch::FinancialPreset.hit_symbols(band: @band).map(&:downcase)
      main_scope = @snapshot.stocks.where(code: hit_codes)
      @t1 = main_scope.where(tier: "T1").order(open_month: :desc, ratio: :asc)
      @t2_p2 = main_scope.where(tier: "T2_P2").order(ratio: :asc)
      @t2_p1 = main_scope.where(tier: "T2_P1").order(ratio: :asc)
      @t3 = main_scope.where(tier: "T3").order(ratio: :asc)
      @overlay = WindowWatch::FinancialPreset.overlay(@t1.to_a + @t2_p2.to_a + @t2_p1.to_a + @t3.to_a)
    else
      @tier = params[:tier].presence_in(WindowWatchSnapshotStock::TIERS)
      @industries = @snapshot.stocks.where.not(industry: "").distinct.order(:industry).pluck(:industry)
      @industry = params[:industry].presence_in(@industries)
      @sort = params[:sort].presence_in(SORT_ORDERS.keys) || "ratio_asc"
      scope = @snapshot.stocks.where({ tier: @tier, industry: @industry }.compact)
      @stocks = scope.order(Arel.sql(SORT_ORDERS.fetch(@sort))).page(params[:page]).per(PAGE_PER)
      @overlay = WindowWatch::FinancialPreset.overlay(@stocks.to_a)
    end
  end
end
