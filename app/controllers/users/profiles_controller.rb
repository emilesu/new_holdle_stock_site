class Users::ProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  after_action :verify_authorized

  def show
    authorize @user
    @api_keys = current_user.api_keys.order(created_at: :desc)
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    if @user.update(user_params)
      redirect_to users_profile_path, notice: "个人信息更新成功"
    else
      render :edit
    end
  rescue StandardError => e
    flash[:alert] = "更新失败：#{e.message}"
    render :edit
  end

  def update_password
    authorize @user, :update_password?
    if @user.update_with_password(password_params)
      bypass_sign_in(@user)
      redirect_to users_profile_path, notice: "密码修改成功"
    else
      render :edit
    end
  rescue StandardError => e
    flash[:alert] = "密码修改失败：#{e.message}"
    render :edit
  end

  # 收藏页每页条数（与金字塔页 PER_PAGE 同风格，前端哨兵由服务端下发避免漂移）
  PER_PAGE = 20
  # 关键词长度上限：超长视为无效查询，直接不过滤（不报错，保证输入即搜永不阻塞）
  MAX_QUERY_LENGTH = 50
  # 金字塔评分区间筛选（0 表示尚未评分）
  SCORE_RANGES = {
    "80_100" => 80..100,
    "60_79"  => 60..79,
    "40_59"  => 40..59,
    "0_39"   => 0..39
  }.freeze

  # 股票收藏页：关键词搜索 + 市场/板块/评分区间筛选 + 排序 + 按市场分组
  # 参数全部白名单化，非法值一律回退为「不过滤」，避免任何参数组合导致 500
  def favorites
    authorize @user
    @is_member = current_user.is_member?
    @q = normalize_query(params[:q])
    @market = whitelist(params[:market], %w[CN HK US])
    @sector_options = favorite_sectors
    @sector = @sector_options.include?(params[:sector].to_s) ? params[:sector].to_s : ""
    # 评分区间筛选与评分排序仅会员可用：非会员直接丢弃参数（防伪造请求绕过会员墙）
    @score_range = @is_member ? whitelist(params[:score_range], SCORE_RANGES.keys) : ""
    @sort = @is_member ? (whitelist(params[:sort], %w[recent score]).presence || "recent") : "recent"
    @group = whitelist(params[:group], %w[market])

    scope = filtered_favorites_scope
    @favorites = scope.order(*order_clause).page(sanitized_page).per(PER_PAGE)
    @total_favorites = @user.user_favorites.count
    @filtered = @q.present? || @market.present? || @sector.present? || @score_range.present?
    # 分组标题跨页去重：排序已保证同一市场连续，故只需知道「上一页最后一行的市场」
    @continued_market = previous_page_last_market(@favorites.current_page)
  end

  # 自助重新生成 Key：就地换（同 id 换新值），流水不断链；旧 key 立即失效
  def regenerate_api_key
    authorize @user
    key = current_user.api_keys.active.first
    if key.nil?
      redirect_to users_profile_path, alert: "没有可重新生成的 Key"
      return
    end

    key.regenerate_plaintext!
    redirect_to users_profile_path, notice: "Key 已重新生成，旧 Key 立即失效，请在所有工具中更新配置"
  rescue StandardError => e
    redirect_to users_profile_path, alert: "重新生成失败：#{e.message}"
  end

  private

  def set_user
    @user = current_user
  end

  def user_params
    params.require(:user).permit(:nickname, :bio)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end

  # 关键词归一化：去首尾与内部多余空白；超长直接丢弃（当作未搜索）
  def normalize_query(value)
    q = value.to_s.squish
    q.length > MAX_QUERY_LENGTH ? "" : q
  end

  # 页码兜底：Kaminari 的 page() 对数组等非字符串参数会直接调用 to_i 抛错
  #（?page[]=1 → NoMethodError → 500），统一转成字符串交给它自行容错
  def sanitized_page
    params[:page].to_s
  end

  # 白名单校验：非法 / 缺失值一律回退为空串（= 不筛选）
  def whitelist(value, allowed)
    v = value.to_s
    allowed.include?(v) ? v : ""
  end

  # 板块下拉选项：取该用户「全部收藏」中出现过的板块，
  # 而不是当前筛选结果里的板块，否则选项会随筛选自我塌缩、用户无法改回
  def favorite_sectors
    @user.user_favorites.joins(:stock)
         .where.not(stocks: { sector: [nil, ""] })
         .distinct
         .order("stocks.sector ASC")
         .pluck("stocks.sector")
  end

  # 收藏查询：includes + references 走 eager_load 单查询，避免行内取 stock 字段时 N+1
  def filtered_favorites_scope
    apply_filters(UserFavorite.where(user: @user).includes(:stock).references(:stock))
  end

  # 「按市场分组」时上一页最后一行的市场：与本页首组相同则本页跳过标题，
  # 避免分组标题跨页重复（排序已保证同一市场的行连续，只有首组可能延续自上一页）
  def previous_page_last_market(page_number)
    return nil unless @group == "market" && page_number > 1

    apply_filters(UserFavorite.where(user: @user).joins(:stock))
      .order(*order_clause)
      .offset((page_number - 1) * PER_PAGE - 1)
      .limit(1)
      .pluck("stocks.market")
      .first
  end

  # 筛选条件（关键词 / 市场 / 板块 / 评分区间），供列表与分组标题去重共用
  def apply_filters(scope)
    if @q.present?
      # 代码 / 名称用模糊匹配；拼音首字母用「前缀」匹配，避免短首字母误命中
      scope = scope.where(
        "stocks.symbol ILIKE :like OR stocks.name ILIKE :like OR stocks.pinyin_initials ILIKE :initials",
        like: "%#{Stock.sanitize_sql_like(@q)}%",
        initials: "#{Stock.sanitize_sql_like(@q.upcase)}%"
      )
    end
    scope = scope.where(stocks: { market: @market }) if @market.present?
    scope = scope.where(stocks: { sector: @sector }) if @sector.present?
    scope = scope.where(stocks: { pyramid_total_score: SCORE_RANGES[@score_range] }) if @score_range.present?
    scope
  end

  # 排序：按市场分组优先 → 指定排序 → 收藏时间倒序
  # eager_load 后 stocks / user_favorites 两表都有 created_at 与 id，必须显式限定表名，
  # 否则 PostgreSQL 会直接抛「列名歧义」错误（order 的嵌套哈希写法也不支持，故用 SQL 片段）
  def order_clause
    orders = []
    if @group == "market"
      orders << Arel.sql("CASE stocks.market WHEN 'CN' THEN 0 WHEN 'HK' THEN 1 WHEN 'US' THEN 2 ELSE 3 END")
    end
    orders << Arel.sql("stocks.pyramid_total_score DESC") if @sort == "score"
    # id 作稳定 tie-breaker，保证分页不重不漏
    orders << Arel.sql("user_favorites.created_at DESC, user_favorites.id DESC")
    orders
  end
end
