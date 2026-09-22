# 股票筛选服务：按「市场 + 板块 + 年度区间 + 盈利指标条件 + 净利润增长条件」实时筛选股票
#
# 数据口径：
# - 盈利指标取 financial_indicators 预存值（roe_avg / gross_margin / net_sales_rate），仅年报（period_type='annual'）
# - 净利润取 income_statements.net_income_to_shareholders（归母净利润），仅年报
# - 美股/港股财年结束日不固定，年份一律用 EXTRACT(YEAR FROM report_date) 判定
class StockScreenerService
  PER_PAGE = 20
  MARKETS = %w[CN HK US].freeze
  MARGIN_MODES = %w[all any last].freeze
  MARGIN_OPS = %w[gte lte].freeze
  GROWTH_MODES = %w[yoy always_up].freeze
  SORTS = %w[pyramid roe_min roe_last ni_growth].freeze
  MIN_YEAR = 1990
  MAX_SPAN = 20

  # 盈利指标定义：表单前缀 => 列名与取值范围
  INDICATORS = {
    'roe' => { column: 'roe_avg', min: -100.0, max: 500.0 },
    'gm'  => { column: 'gross_margin', min: -100.0, max: 100.0 },
    'npm' => { column: 'net_sales_rate', min: -100.0, max: 100.0 }
  }.freeze

  LABELS = { 'roe' => 'ROE', 'gm' => '毛利率', 'npm' => '净利率' }.freeze

  class Result
    attr_accessor :stocks, :total_count, :total_pages, :page, :metrics, :errors, :conditions
    attr_writer :has_more

    def initialize
      @errors = []
      @metrics = {}
      @conditions = {}
      @stocks = []
      @total_count = 0
      @total_pages = 0
      @page = 1
    end

    def ok?
      @errors.empty?
    end

    def has_more?
      !!@has_more
    end
  end

  def self.call(params)
    new(params).call
  end

  def initialize(params)
    # 统一为字符串键：兼容 ActionController::Parameters（未 permit 时 to_h 会抛异常）与普通 Hash（符号键）
    raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    @params = raw.to_h.transform_keys(&:to_s)
    @result = Result.new
    @margin_conditions = []
  end

  def call
    parse!
    return @result unless @result.ok?

    ids_scope = base_scope
    # 子查询 SQL 已由 sanitize_sql_array 完成参数化，可安全内联；不能用 where(id: 字符串)，那会被当作字面值绑定
    ids_scope = ids_scope.where("stocks.id IN (#{margin_ids_sql})") unless @margin_conditions.empty?
    ids_scope = ids_scope.where("stocks.id IN (#{growth_ids_sql})") if @growth_mode

    @result.total_count = ids_scope.count
    @result.total_pages = (@result.total_count.to_f / PER_PAGE).ceil
    # 越界页码钳制到末页，避免误显示「没有符合条件的股票」
    @page = @page.clamp(1, [@result.total_pages, 1].max)
    @result.page = @page

    page_stocks = ordered_stocks(ids_scope).offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @result.has_more = @page < @result.total_pages
    @result.stocks = page_stocks
    @result.metrics = load_metrics(page_stocks)
    @result
  end

  private

  # ---------- 参数解析与校验 ----------

  def parse!
    @market = @params['market'].to_s
    unless MARKETS.include?(@market)
      reject! '请选择有效的市场'
      return
    end

    @sector = @params['sector'].to_s.strip
    @sector = nil if @sector.empty? || @sector == 'all'

    latest_year = Date.current.year - 1 # 当年年报未披露完毕，默认区间截至上一完整财年
    @year_to = int_param(:year_to) || latest_year
    @year_from = int_param(:year_from) || (@year_to - 4)

    unless @year_from.between?(MIN_YEAR, latest_year) && @year_to.between?(MIN_YEAR, latest_year) && @year_from <= @year_to
      reject! "年度区间无效（须在 #{MIN_YEAR} ~ #{latest_year} 之间，且起始年不晚于结束年）"
      return
    end
    if @year_to - @year_from + 1 > MAX_SPAN
      reject! "年度区间跨度不能超过 #{MAX_SPAN} 年"
      return
    end
    @year_span = @year_to - @year_from + 1

    @margin_mode = @params['margin_mode'].to_s
    @margin_mode = 'all' if @margin_mode.empty?
    unless MARGIN_MODES.include?(@margin_mode)
      reject! '盈利判定口径无效'
      return
    end

    parse_margin_conditions
    unless @result.ok?
      @result.conditions = raw_conditions
      return
    end

    @growth_mode = @params['growth_mode'].to_s.presence
    if @growth_mode.present? && !GROWTH_MODES.include?(@growth_mode)
      reject! '净利润增长模式无效'
      return
    end
    @growth_value = float_param(:growth_value)
    if @growth_mode == 'yoy'
      if @growth_value.nil? || !@growth_value.between?(-100.0, 1000.0)
        reject! '请填写有效的净利润同比增长阈值（-100 ~ 1000）'
        return
      end
    elsif @growth_mode == 'always_up' && @year_span < 2
      reject! '「区间内逐年上升」需要至少 2 个年度'
      return
    end

    if @margin_conditions.empty? && @growth_mode.nil?
      reject! '请至少设置一个筛选条件'
      return
    end

    @sort = @params['sort'].to_s.presence || 'pyramid'
    unless SORTS.include?(@sort)
      reject! '排序方式无效'
      return
    end

    @page = [[int_param(:page).to_i, 1].max, 1_000].min

    @result.conditions = {
      market: @market, sector: @sector, year_from: @year_from, year_to: @year_to,
      margin_mode: @margin_mode, margin_conditions: @margin_conditions,
      growth_mode: @growth_mode, growth_value: @growth_value, sort: @sort
    }
  end

  # 记录校验错误并回填原始输入，供表单保留用户已填内容
  def reject!(msg)
    @result.errors << msg
    @result.conditions = raw_conditions
  end

  # 宽容回显参数：校验失败时尽量还原用户输入（阈值即使越界也原样保留）
  def raw_conditions
    margin_conditions = INDICATORS.filter_map do |key, meta|
      raw = @params["#{key}_value"].to_s.strip
      next if raw.empty?
      value = parse_float(raw)
      next if value.nil?
      op = @params["#{key}_op"].to_s
      op = 'gte' unless MARGIN_OPS.include?(op)
      { key: key, column: meta[:column], op: op, value: value }
    end
    {
      market: @params['market'].to_s,
      sector: @params['sector'].to_s.strip.presence,
      year_from: int_param(:year_from),
      year_to: int_param(:year_to),
      margin_mode: @params['margin_mode'].to_s.presence || 'all',
      margin_conditions: margin_conditions,
      growth_mode: @params['growth_mode'].to_s.presence,
      growth_value: float_param(:growth_value),
      sort: @params['sort'].to_s.presence || 'pyramid'
    }
  end

  def parse_margin_conditions
    @margin_conditions = []
    INDICATORS.each do |key, meta|
      raw = @params["#{key}_value"].to_s.strip
      next if raw.empty?

      value = parse_float(raw)
      if value.nil? || !value.between?(meta[:min], meta[:max])
        @result.errors << "#{LABELS[key]}阈值无效（#{meta[:min]} ~ #{meta[:max]}）"
        next
      end

      op = @params["#{key}_op"].to_s
      op = 'gte' unless MARGIN_OPS.include?(op)
      @margin_conditions << { key: key, column: meta[:column], op: op, value: value }
    end
  end

  def parse_float(raw)
    Float(raw)
  rescue ArgumentError, TypeError
    nil
  end

  def int_param(name)
    raw = @params[name.to_s].to_s.strip
    return nil if raw.empty?
    Integer(raw, 10)
  rescue ArgumentError
    nil
  end

  def float_param(name)
    raw = @params[name.to_s].to_s.strip
    return nil if raw.empty?
    parse_float(raw)
  end

  # ---------- 查询构建（SQL 全参数化，列名/枚举均来自白名单常量） ----------

  def base_scope
    scope = Stock.where(market: @market, status: 'listed')
    scope = scope.where(sector: @sector) if @sector
    scope
  end

  # 盈利条件命中的 stock_id 子查询；无启用指标时返回恒空集
  def margin_ids_sql
    return 'SELECT -1' if @margin_conditions.empty?

    thresholds = @margin_conditions.map { |c| c[:value] }

    case @margin_mode
    when 'all'
      # 区间内每个年度都有年报，且每个启用指标全年度非空并全部达标
      having = ['COUNT(DISTINCT EXTRACT(YEAR FROM report_date)) = ' + @year_span.to_i.to_s]
      @margin_conditions.each do |c|
        # 按「非空值覆盖的年度数」判定，避免财年切换导致同年多条年报时误排除
        having << "COUNT(DISTINCT CASE WHEN #{c[:column]} IS NOT NULL THEN EXTRACT(YEAR FROM report_date) END) = #{@year_span.to_i}"
        if c[:op] == 'gte'
          having << "MIN(#{c[:column]}) >= ?"
        else
          having << "MAX(#{c[:column]}) <= ?"
        end
      end
      sql = "SELECT stock_id FROM financial_indicators WHERE period_type = 'annual' AND market = ? AND report_date BETWEEN ? AND ? GROUP BY stock_id HAVING #{having.join(' AND ')}"
      sanitize(sql, [@market, date_from, date_to] + thresholds)
    when 'any'
      having = @margin_conditions.map do |c|
        c[:op] == 'gte' ? "MAX(#{c[:column]}) >= ?" : "MIN(#{c[:column]}) <= ?"
      end
      sql = "SELECT stock_id FROM financial_indicators WHERE period_type = 'annual' AND market = ? AND report_date BETWEEN ? AND ? GROUP BY stock_id HAVING #{having.join(' AND ')}"
      sanitize(sql, [@market, date_from, date_to] + thresholds)
    when 'last'
      conds = @margin_conditions.map do |c|
        c[:op] == 'gte' ? "#{c[:column]} >= ?" : "#{c[:column]} <= ?"
      end
      null_conds = @margin_conditions.map { |c| "#{c[:column]} IS NOT NULL" }
      sql = "SELECT DISTINCT stock_id FROM financial_indicators WHERE period_type = 'annual' AND market = ? AND report_date BETWEEN ? AND ? AND #{(null_conds + conds).join(' AND ')}"
      sanitize(sql, [@market, last_year_date_from, last_year_date_to] + thresholds)
    end
  end

  # 净利润增长条件命中的 stock_id 子查询；未启用时返回恒空集（调用方仅在启用时才会用到结果）
  def growth_ids_sql
    return 'SELECT -1' if @growth_mode.nil?

    case @growth_mode
    when 'yoy'
      sql = "SELECT cur.stock_id FROM income_statements cur " \
            "JOIN income_statements prev ON prev.stock_id = cur.stock_id AND prev.period_type = 'annual' AND prev.market = cur.market AND EXTRACT(YEAR FROM prev.report_date) = ? " \
            "WHERE cur.period_type = 'annual' AND cur.market = ? AND EXTRACT(YEAR FROM cur.report_date) = ? " \
            "AND prev.net_income_to_shareholders > 0 AND cur.net_income_to_shareholders IS NOT NULL " \
            "AND (cur.net_income_to_shareholders - prev.net_income_to_shareholders) / ABS(prev.net_income_to_shareholders) * 100 >= ?"
      sanitize(sql, [@year_to - 1, @market, @year_to, @growth_value])
    when 'always_up'
      sql = "SELECT stock_id FROM (" \
            "SELECT stock_id, report_date AS rd, net_income_to_shareholders AS v, " \
            "LAG(net_income_to_shareholders) OVER (PARTITION BY stock_id ORDER BY report_date) AS pv " \
            "FROM income_statements WHERE period_type = 'annual' AND market = ? AND report_date BETWEEN ? AND ?" \
            ") t GROUP BY stock_id " \
            "HAVING COUNT(DISTINCT EXTRACT(YEAR FROM rd)) = ? AND SUM(CASE WHEN v IS NULL THEN 1 ELSE 0 END) = 0 " \
            "AND SUM(CASE WHEN pv IS NOT NULL AND v <= pv THEN 1 ELSE 0 END) = 0"
      sanitize(sql, [@market, date_from, date_to, @year_span])
    end
  end

  def ordered_stocks(ids_scope)
    case @sort
    when 'pyramid'
      ids_scope.order(pyramid_total_score: :desc, id: :desc)
    when 'roe_min', 'roe_last'
      col = @sort == 'roe_min' ? 'agg.roe_min' : 'agg.roe_last'
      # LEFT JOIN：无指标行的股票不丢弃，排在末尾（NULLS LAST）
      ids_scope.joins("LEFT JOIN (#{margin_agg_sql}) agg ON agg.stock_id = stocks.id")
              .order(Arel.sql("#{col} DESC NULLS LAST, stocks.pyramid_total_score DESC, stocks.id DESC"))
              .select('stocks.*')
    when 'ni_growth'
      ids_scope.joins("LEFT JOIN (#{growth_yoy_agg_sql}) agg ON agg.stock_id = stocks.id")
              .order(Arel.sql('agg.growth DESC NULLS LAST, stocks.pyramid_total_score DESC, stocks.id DESC'))
              .select('stocks.*')
    end
  end

  # 盈利指标聚合（排序用）：区间内最低 ROE / 末年 ROE。年份为已校验整数，可安全内联
  def margin_agg_sql
    "SELECT stock_id, MIN(roe_avg) AS roe_min, " \
    "MAX(CASE WHEN EXTRACT(YEAR FROM report_date) = #{@year_to} THEN roe_avg END) AS roe_last " \
    "FROM financial_indicators " \
    "WHERE period_type = 'annual' AND market = #{ActiveRecord::Base.connection.quote(@market)} " \
    "AND report_date BETWEEN #{ActiveRecord::Base.connection.quote(date_from)} AND #{ActiveRecord::Base.connection.quote(date_to)} " \
    "GROUP BY stock_id"
  end

  # 净利润同比聚合（排序用）
  def growth_yoy_agg_sql
    quote = ActiveRecord::Base.connection.method(:quote)
    # GROUP BY 防同年多条年报时 LEFT JOIN 放大行数导致分页结果重复
    "SELECT cur.stock_id, MAX(" \
    "(cur.net_income_to_shareholders - prev.net_income_to_shareholders) / ABS(prev.net_income_to_shareholders) * 100) AS growth " \
    "FROM income_statements cur " \
    "JOIN income_statements prev ON prev.stock_id = cur.stock_id AND prev.period_type = 'annual' AND prev.market = cur.market " \
    "AND EXTRACT(YEAR FROM prev.report_date) = #{@year_to - 1} " \
    "WHERE cur.period_type = 'annual' AND cur.market = #{quote.call(@market)} AND EXTRACT(YEAR FROM cur.report_date) = #{@year_to} " \
    "AND prev.net_income_to_shareholders > 0 AND cur.net_income_to_shareholders IS NOT NULL " \
    "GROUP BY cur.stock_id"
  end

  # ---------- 结果指标加载（展示用，单页各一次聚合查询，避免 N+1） ----------

  def load_metrics(stocks)
    return {} if stocks.empty?

    ids = stocks.map(&:id)
    metrics = {}
    year_to = @year_to.to_i

    # 占位符顺序：SELECT 中三个 CASE 年份在前，WHERE 中 ids/market/日期在后
    fi_sql = sanitize(<<~SQL, [year_to, year_to, year_to, ids, @market, date_from, date_to])
      SELECT stock_id,
             MIN(roe_avg) AS roe_min,
             MAX(CASE WHEN EXTRACT(YEAR FROM report_date) = ? THEN roe_avg END) AS roe_last,
             MAX(CASE WHEN EXTRACT(YEAR FROM report_date) = ? THEN gross_margin END) AS gm_last,
             MAX(CASE WHEN EXTRACT(YEAR FROM report_date) = ? THEN net_sales_rate END) AS npm_last
      FROM financial_indicators
      WHERE stock_id IN (?) AND period_type = 'annual' AND market = ? AND report_date BETWEEN ? AND ?
      GROUP BY stock_id
    SQL
    ActiveRecord::Base.connection.select_all(fi_sql).each do |row|
      metrics[row['stock_id'].to_i] = {
        roe_min: row['roe_min']&.to_f, roe_last: row['roe_last']&.to_f,
        gm_last: row['gm_last']&.to_f, npm_last: row['npm_last']&.to_f
      }
    end

    growth_sql = sanitize(<<~SQL, [ids, @market, year_to, year_to - 1])
      SELECT cur.stock_id,
             (cur.net_income_to_shareholders - prev.net_income_to_shareholders) / ABS(prev.net_income_to_shareholders) * 100 AS growth
      FROM income_statements cur
      JOIN income_statements prev ON prev.stock_id = cur.stock_id AND prev.period_type = 'annual' AND prev.market = cur.market
      WHERE cur.stock_id IN (?) AND cur.period_type = 'annual' AND cur.market = ?
        AND EXTRACT(YEAR FROM cur.report_date) = ? AND EXTRACT(YEAR FROM prev.report_date) = ?
        AND prev.net_income_to_shareholders > 0 AND cur.net_income_to_shareholders IS NOT NULL
    SQL
    ActiveRecord::Base.connection.select_all(growth_sql).each do |row|
      m = metrics[row['stock_id'].to_i] ||= {}
      m[:ni_growth] = row['growth']&.to_f
    end

    metrics
  end

  # ---------- 工具 ----------

  def date_from
    "#{@year_from}-01-01"
  end

  def date_to
    "#{@year_to}-12-31"
  end

  def last_year_date_from
    "#{@year_to}-01-01"
  end

  def last_year_date_to
    "#{@year_to}-12-31"
  end

  def sanitize(sql, binds)
    ActiveRecord::Base.sanitize_sql_array([sql, *binds])
  end
end
