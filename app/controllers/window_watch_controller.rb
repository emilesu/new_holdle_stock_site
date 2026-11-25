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
    # R2②：月份切换（历史快照回看）；非法/不存在月份回落 latest（格式权威源=契约边界 SnapshotIngest）
    month_param = params[:month].to_s
    @snapshot = (month_param.match?(WindowWatch::SnapshotIngest::MONTH_FORMAT) && WindowWatchSnapshot.find_by(month: month_param)) ||
                WindowWatchSnapshot.latest
    @is_member = user_signed_in? && current_user.content_tier >= User::TIER_MEMBER
    return unless @snapshot && @is_member

    @months = WindowWatchSnapshot.recent_first.limit(24).pluck(:month)

    # R1：视图开关只切 main/all，筛选条件随视图重置（行为一致）
    @view = params[:view] == "all" ? "all" : "main"
    if @view == "main"
      # 财务预设视图（2026-11-25 老板定三维筛选）：年数(3/5) × 满足方式(连续/平均) × ROE阈值(10/15/20)
      # 命中集与 ROE 筛选主值均来自财务库；④持仓管理同样跟随预设（老板 2026-11-25 定，推翻「排除桶全量」旧口径）
      # R1 排序：金字塔综合分降序（同分贴0轴比值升序）；分数缺失（join 未命中）排末位
      @band = WindowWatch::FinancialPreset.band_for(params[:band])
      @years = WindowWatch::FinancialPreset.years_for(params[:years])
      @mode = WindowWatch::FinancialPreset.mode_for(params[:mode])
      metrics = WindowWatch::FinancialPreset.preset_metrics(years: @years, mode: @mode, band: @band)
      @preset_metrics = metrics.transform_keys(&:downcase) # 键=快照 code（小写）
      hit_codes = @preset_metrics.keys
      main_scope = @snapshot.stocks
                           .joins("LEFT JOIN stocks ON lower(stocks.symbol) = window_watch_snapshot_stocks.code")
                           .where(code: hit_codes)
                           .order(Arel.sql("stocks.pyramid_total_score DESC NULLS LAST, window_watch_snapshot_stocks.ratio ASC"))
      @t1 = main_scope.where(tier: "T1").to_a
      @t2_p2 = main_scope.where(tier: "T2_P2").to_a
      @t2_p1 = main_scope.where(tier: "T2_P1").to_a
      @t3 = main_scope.where(tier: "T3").to_a
      @in_position = main_scope.where(tier: WindowWatchSnapshotStock::IN_POSITION).to_a
      # v1.1 快照无 IN_POSITION 行 → 降级仅计数提示（计数=stats 全量口径，无法按预设过滤）
      @in_position_degraded = !@snapshot.stocks.where(tier: WindowWatchSnapshotStock::IN_POSITION).exists?
      # 计数条=命中子集计数，随三维控件变化（2026-11-25 老板定）
      @preset_counts = { "T1" => @t1.size, "T2_P2" => @t2_p2.size, "T2_P1" => @t2_p1.size, "T3" => @t3.size,
                         "IN_POSITION" => @in_position_degraded ? @snapshot.stats["in_position_count"].to_i : @in_position.size }
      all_rows = @t1 + @t2_p2 + @t2_p1 + @t3 + @in_position
      @overlay = WindowWatch::FinancialPreset.overlay(all_rows)
      # R2③：卡片近 6 月 sparkline
      @sparkline = WindowWatch::MonthlySparkline.call(all_rows, snapshot_month: @snapshot.month)
      prepare_row_extras
    else
      @tier = params[:tier].presence_in(WindowWatchSnapshotStock::ALL_TIERS)
      @industries = @snapshot.stocks.where.not(industry: "").distinct.order(:industry).pluck(:industry)
      @industry = params[:industry].presence_in(@industries)
      @sort = params[:sort].presence_in(SORT_ORDERS.keys) || "ratio_asc"
      # 列名预先限定表名：q 检索分支会 LEFT JOIN stocks（industry/name 两表同名，防歧义）
      scope = @snapshot.stocks.where({"window_watch_snapshot_stocks.tier" => @tier,
                                      "window_watch_snapshot_stocks.industry" => @industry}.compact)
      # R2①：名称/代码检索（通配符与转义符剥离后整串模糊匹配，参数化查询防注入）；
      # 同时匹配当前库名（评审修复5）：改名股按现名可命中，展示名与检索词不再错位；
      # stocks.symbol 唯一索引保证 1:1，join 不改变行数；列名全部限定防歧义
      @q = params[:q].to_s.strip.delete("%_\\")[0, 40]
      if @q.present?
        like = "%#{@q}%"
        scope = scope
                .joins("LEFT JOIN stocks ON lower(stocks.symbol) = window_watch_snapshot_stocks.code")
                .where("window_watch_snapshot_stocks.name ILIKE :q OR window_watch_snapshot_stocks.code ILIKE :q OR " \
                       "window_watch_snapshot_stocks.symbol ILIKE :q OR stocks.name ILIKE :q", q: like)
      end
      @stocks = scope.order(Arel.sql(SORT_ORDERS.fetch(@sort))).page(params[:page]).per(PAGE_PER)
      @overlay = WindowWatch::FinancialPreset.overlay(@stocks.to_a)
      # ⑥（2026-11-25 老板定）：全量视图与预设视图统一卡片样式 → 同样装配 sparkline 与行内收藏数据
      @sparkline = WindowWatch::MonthlySparkline.call(@stocks.to_a, snapshot_month: @snapshot.month)
      prepare_row_extras
    end
  end

  private

  # 卡片行收藏态=纯展示标记（2026-11-25 老板更正）：已收藏打星、未收藏无星标；
  # 收藏交互入口在个股详情页，本页不做行内表单。Stock 对象复用 overlay 已加载结果（评审修复2）
  def prepare_row_extras
    stock_ids = @overlay.filter_map { |_sym, ov| ov[:stock]&.id }
    @favorite_stock_ids = current_user.user_favorites.where(stock_id: stock_ids).pluck(:stock_id).to_set
  end
end
