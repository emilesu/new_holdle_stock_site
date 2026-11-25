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
  MONTH_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/

  def index
    if DARK_RELEASE && !(user_signed_in? && current_user.is_admin?)
      redirect_to root_path and return
    end
    # R2②：月份切换（历史快照回看）；非法/不存在月份回落 latest
    month_param = params[:month].to_s
    @snapshot = (month_param.match?(MONTH_FORMAT) && WindowWatchSnapshot.find_by(month: month_param)) ||
                WindowWatchSnapshot.latest
    @is_member = user_signed_in? && current_user.content_tier >= User::TIER_MEMBER
    return unless @snapshot && @is_member

    @months = WindowWatchSnapshot.recent_first.limit(24).pluck(:month)

    # R1：视图开关只切 main/all，筛选条件随视图重置（行为一致）
    @view = params[:view] == "all" ? "all" : "main"
    if @view == "main"
      # 财务预设视图：命中集来自财务库（近3财年 ROE≥档位 且 经营现金流>0，最新披露口径）
      # R1 排序：金字塔综合分降序（同分贴0轴比值升序），取消 T1 开窗月排序；分数缺失（join 未命中）排末位
      # 四档直接落数组：视图 size/迭代零额外查询（评审修复2）
      @band = WindowWatch::FinancialPreset.band_for(params[:band])
      hit_codes = WindowWatch::FinancialPreset.hit_symbols(band: @band).map(&:downcase)
      main_scope = @snapshot.stocks
                           .joins("LEFT JOIN stocks ON lower(stocks.symbol) = window_watch_snapshot_stocks.code")
                           .where(code: hit_codes)
                           .order(Arel.sql("stocks.pyramid_total_score DESC NULLS LAST, window_watch_snapshot_stocks.ratio ASC"))
      @t1 = main_scope.where(tier: "T1").to_a
      @t2_p2 = main_scope.where(tier: "T2_P2").to_a
      @t2_p1 = main_scope.where(tier: "T2_P1").to_a
      @t3 = main_scope.where(tier: "T3").to_a
      # R3④：持仓管理区块（契约 v0.5）：不受财务预设过滤（排除桶是状态描述），金字塔序 top10+折叠；
      # v1.1 无逐股行时降级为仅计数提示（in_position_count 兜底）
      @in_position = @snapshot.stocks
                              .joins("LEFT JOIN stocks ON lower(stocks.symbol) = window_watch_snapshot_stocks.code")
                              .where(tier: WindowWatchSnapshotStock::IN_POSITION)
                              .order(Arel.sql("stocks.pyramid_total_score DESC NULLS LAST, window_watch_snapshot_stocks.ratio ASC"))
                              .to_a
      @in_position_count = [@snapshot.stats["in_position_count"].to_i, @in_position.size].max
      all_rows = @t1 + @t2_p2 + @t2_p1 + @t3 + @in_position
      @overlay = WindowWatch::FinancialPreset.overlay(all_rows)
      # R2③：卡片近 6 月 sparkline（全量表格视图不装配，控制查询规模）
      @sparkline = WindowWatch::MonthlySparkline.call(all_rows, snapshot_month: @snapshot.month)
    else
      @tier = params[:tier].presence_in(WindowWatchSnapshotStock::ALL_TIERS)
      @industries = @snapshot.stocks.where.not(industry: "").distinct.order(:industry).pluck(:industry)
      @industry = params[:industry].presence_in(@industries)
      @sort = params[:sort].presence_in(SORT_ORDERS.keys) || "ratio_asc"
      scope = @snapshot.stocks.where({ tier: @tier, industry: @industry }.compact)
      # R2①：名称/代码检索（通配符与转义符剥离后整串模糊匹配，参数化查询防注入）
      @q = params[:q].to_s.strip.delete("%_\\")[0, 40]
      if @q.present?
        like = "%#{@q}%"
        scope = scope.where("name ILIKE :q OR code ILIKE :q OR symbol ILIKE :q", q: like)
      end
      @stocks = scope.order(Arel.sql(SORT_ORDERS.fetch(@sort))).page(params[:page]).per(PAGE_PER)
      @overlay = WindowWatch::FinancialPreset.overlay(@stocks.to_a)
    end
  end
end
