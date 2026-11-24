# 月K开窗观察（需求单 01 v0.3）：只读 DSH 月批快照，页面零判定计算、零绝对数值渲染
# 访问控制（§一）：会员可见完整列表；非会员/未登录 = 定位说明 + 四档计数 teaser（不查行表，V12）
class WindowWatchController < ApplicationController
  # 全量视图排序白名单（R3/A6：禁止参数直接透传 SQL）
  SORT_ORDERS = {
    "ratio_asc" => "ratio ASC", "ratio_desc" => "ratio DESC",
    "open_month_desc" => "open_month DESC NULLS LAST",
    "sa_run_desc" => "sa_run DESC"
  }.freeze
  PAGE_PER = 100

  def index
    @snapshot = WindowWatchSnapshot.latest
    @is_member = user_signed_in? && current_user.content_tier >= User::TIER_MEMBER
    return unless @snapshot && @is_member

    # R1：视图开关只切 main/all，筛选条件随视图重置（行为一致）
    @view = params[:view] == "all" ? "all" : "main"
    if @view == "main"
      main_scope = @snapshot.stocks.where(run3_asof: true)
      @t1 = main_scope.where(tier: "T1").order(open_month: :desc, ratio: :asc)
      @t2_p2 = main_scope.where(tier: "T2_P2").order(ratio: :asc)
      @t2_p1 = main_scope.where(tier: "T2_P1").order(ratio: :asc)
      @t3 = main_scope.where(tier: "T3").order(ratio: :asc)
    else
      @tier = params[:tier].presence_in(WindowWatchSnapshotStock::TIERS)
      @industries = @snapshot.stocks.where.not(industry: "").distinct.order(:industry).pluck(:industry)
      @industry = params[:industry].presence_in(@industries)
      @sort = params[:sort].presence_in(SORT_ORDERS.keys) || "ratio_asc"
      scope = @snapshot.stocks.where({ tier: @tier, industry: @industry }.compact)
      @stocks = scope.order(Arel.sql(SORT_ORDERS.fetch(@sort))).page(params[:page]).per(PAGE_PER)
    end
  end
end
