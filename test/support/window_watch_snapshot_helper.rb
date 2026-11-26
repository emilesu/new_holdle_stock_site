# 开窗快照测试支撑（契约 v0.7.0：快照不携带任何财务字段；北交所纳入所有档/桶，bj_count 键退役；
# v0.8 多市场：US fixture + ww_payload market 参数，CN fixture 原样零改动）
# 数值刻意取 6 位小数长尾形态，便于 V11 断言「绝对数值未渲染」（两位小数形态也逐一检查）
module WindowWatchSnapshotHelper
  WW_DISCLAIMER = "本页面为按 HOLDLE 方法论对股票月K状态的客观描述，不构成投资建议，不构成任何买卖推荐。方法论基于历史规律总结，过去的状态表现不代表未来。数据截至 2026-10 月K收盘，价格按前复权口径，除权后历史价格会变动；页面不包含盘中实时行情。请独立判断并自行承担决策责任。"

  WW_STOCKS = [
    { symbol: "601985.SH", code: "sh601985", name: "中国核电", industry: "电力", exchange: "SH",
      tier: "T1", subtag: "", hist: "1.234567", prev_hist: "0.765432",
      dif: "1.555555", dea: "0.987654", ratio: "1.250001",
      open_month: "2026-08", months_since_open: 3, last_close_month: nil, sa_run: 7 },
    { symbol: "600036.SH", code: "sh600036", name: "招商银行", industry: "银行", exchange: "SH",
      tier: "T1", subtag: "", hist: "2.345678", prev_hist: "1.876543",
      dif: "2.111111", dea: "1.444444", ratio: "1.623457",
      open_month: "2026-10", months_since_open: 1, last_close_month: nil, sa_run: 9 },
    { symbol: "000333.SZ", code: "sz000333", name: "美的集团", industry: "家电", exchange: "SZ",
      tier: "T2_P2", subtag: "continuation", hist: "0.555555", prev_hist: "0.888888",
      dif: "0.666666", dea: "0.444444", ratio: "1.250002",
      open_month: nil, months_since_open: nil, last_close_month: "2026-09", sa_run: 4 },
    { symbol: "000858.SZ", code: "sz000858", name: "五粮液", industry: "白酒", exchange: "SZ",
      tier: "T2_P2", subtag: "sticky_micro", hist: "0.001234", prev_hist: "0.023456",
      dif: "0.015555", dea: "0.041111", ratio: "0.024999",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 2 },
    { symbol: "600519.SH", code: "sh600519", name: "贵州茅台", industry: "白酒", exchange: "SH",
      tier: "T2_P1", subtag: "", hist: "-0.345678", prev_hist: "-0.654321",
      dif: "0.555555", dea: "0.722222", ratio: "0.478630",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 3 },
    { symbol: "300750.SZ", code: "sz300750", name: "宁德时代", industry: "电池", exchange: "SZ",
      tier: "T3", subtag: "high_gate", hist: "3.456789", prev_hist: "2.987654",
      dif: "2.555555", dea: "1.876543", ratio: "1.842087",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 12 }
  ].freeze

  # 契约 v1.2 IN_POSITION 逐股明细 fixture（05 变更单 §1.2）：
  # 泸州老窖 entry_month=2026-11 晚于判定月 2026-10 —— 口径②实测正常形态，页面不得拒绝
  WW_IN_POSITION = [
    { symbol: "601318.SH", code: "sh601318", name: "中国平安", industry: "保险", exchange: "SH",
      tier: "IN_POSITION", subtag: "", hist: "-1.111111", prev_hist: "-2.222222",
      dif: "0.333333", dea: "0.444444", ratio: "0.555556",
      open_month: "2025-03", months_since_open: 19, last_close_month: nil, sa_run: 20,
      entry_month: "2025-06", months_in_position: 16 },
    { symbol: "000568.SZ", code: "sz000568", name: "泸州老窖", industry: "白酒", exchange: "SZ",
      tier: "IN_POSITION", subtag: "", hist: "-0.123456", prev_hist: "-0.654321",
      dif: "0.111111", dea: "0.222222", ratio: "0.333333",
      open_month: "2026-02", months_since_open: 8, last_close_month: nil, sa_run: 8,
      entry_month: "2026-11", months_in_position: 1 }
  ].freeze

  # ---- 契约 v0.8 US fixture：symbol=<YAHOO码>.US、code=裸 Yahoo 码（BRK.A 带点码消歧样本）、exchange 恒 US ----
  WW_US_DISCLAIMER = "本页面为按 HOLDLE 方法论对美股月K状态的客观描述，覆盖范围为普通股与美国存托凭证（ADR），不构成投资建议，不构成任何买卖推荐。方法论基于历史规律总结，过去的状态表现不代表未来。数据截至 2026-10 月K收盘，价格按前复权口径，除权/拆股/分红后历史价格会变动；页面不包含盘中实时行情。请独立判断并自行承担决策责任。"

  WW_US_STOCKS = [
    { symbol: "NVDA.US", code: "NVDA", name: "英伟达", industry: "Information Technology", exchange: "US",
      tier: "T1", subtag: "", hist: "0.987654", prev_hist: "1.234567",
      dif: "1.111111", dea: "0.666666", ratio: "1.481482",
      open_month: "2026-07", months_since_open: 4, last_close_month: nil, sa_run: 8 },
    { symbol: "BRK.A.US", code: "BRK.A", name: "伯克希尔哈撒韦A", industry: "Financials", exchange: "US",
      tier: "T2_P2", subtag: "continuation", hist: "0.456789", prev_hist: "0.789012",
      dif: "0.555555", dea: "0.333333", ratio: "1.370371",
      open_month: nil, months_since_open: nil, last_close_month: "2026-09", sa_run: 5 },
    { symbol: "ABEV.US", code: "ABEV", name: "Ambev ADR", industry: "Consumer Staples", exchange: "US",
      tier: "T2_P1", subtag: "", hist: "-0.246813", prev_hist: "-0.468135",
      dif: "0.333333", dea: "0.555555", ratio: "0.444444",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 2 },
    { symbol: "UBER.US", code: "UBER", name: "Uber", industry: "Industrials", exchange: "US",
      tier: "T3", subtag: "high_gate", hist: "2.468135", prev_hist: "1.357911",
      dif: "1.999999", dea: "1.111111", ratio: "1.800000",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 6 }
  ].freeze

  WW_US_IN_POSITION = [
    { symbol: "AAPL.US", code: "AAPL", name: "苹果", industry: "Information Technology", exchange: "US",
      tier: "IN_POSITION", subtag: "", hist: "-0.987654", prev_hist: "-1.234567",
      dif: "0.246813", dea: "0.864197", ratio: "0.285618",
      open_month: "2025-01", months_since_open: 21, last_close_month: nil, sa_run: 22,
      entry_month: "2025-04", months_in_position: 18 }
  ].freeze

  # 美股金字塔分/板块 fixture（站内 stocks 表字段，不进快照 payload）
  WW_US_PYRAMID = { "NVDA" => 88, "BRK.A" => 82, "ABEV" => 55, "UBER" => 48, "AAPL" => 90 }.freeze
  # 板块 fixture（对齐库内美股中文 GICS 映射实际值：金融服务/科技/消费防御/工业）
  WW_US_SECTORS = { "NVDA" => "科技", "BRK.A" => "金融服务", "ABEV" => "消费防御", "UBER" => "工业", "AAPL" => "科技" }.freeze

  # 站内金字塔综合分 fixture（R1 预设视图排序依据；stocks 表自有字段，不进快照 payload）
  WW_PYRAMID_SCORES = { "SH601985" => 70, "SH600036" => 85, "SZ000333" => 60,
                        "SZ000858" => 40, "SH600519" => 90, "SZ300750" => 50,
                        "SH601318" => 65, "SZ000568" => 45 }.freeze
  # 板块 fixture（2026-11-25 老板定：卡片显示板块 · 行业）
  WW_SECTORS = { "SH601985" => "公用事业", "SH600036" => "金融", "SZ000333" => "消费",
                 "SZ000858" => "消费", "SH600519" => "消费", "SZ300750" => "制造",
                 "SH601318" => "金融", "SZ000568" => "消费" }.freeze

  # 站内 stocks 表落库（code 命中校验 + 财务库 overlay + 金字塔排序用）
  def ww_create_stocks!
    (WW_STOCKS + WW_IN_POSITION).each do |r|
      code, ex = r[:symbol].split(".")
      Stock.create!(symbol: "#{ex}#{code}", name: r[:name], market: "CN",
                    exchange: "#{ex}SE", industry: r[:industry], status: "active",
                    sector: WW_SECTORS["#{ex}#{code}"],
                    pyramid_total_score: WW_PYRAMID_SCORES["#{ex}#{code}"])
    end
  end

  # v0.8：美股站内条目=裸 Yahoo 码（NasdaqStockListService 现约定），exchange 为交易所名
  # AAPL 已在 stocks.yml fixtures（symbol=AAPL/market=US）——first_or_create 幂等，不重复建
  def ww_create_us_stocks!
    exch = { "NVDA" => "NASDAQ", "BRK.A" => "NYSE", "ABEV" => "NYSE", "UBER" => "NYSE", "AAPL" => "NASDAQ" }
    (WW_US_STOCKS + WW_US_IN_POSITION).each do |r|
      Stock.where(symbol: r[:code], market: "US").first_or_create!(
        name: r[:name], exchange: exch[r[:code]], industry: r[:industry], status: "listed",
        sector: WW_US_SECTORS[r[:code]], pyramid_total_score: WW_US_PYRAMID[r[:code]]
      )
    end
  end

  # v0.8：美股财务喂数——财年截止日刻意取 10-31（非 12-31），验证 US 预设「最近 N 份年报」口径
  def ww_give_us_financials(symbol, roes:, ocfs: nil)
    stock = Stock.find_by!(symbol: symbol, market: "US")
    years = WindowWatch::FinancialPreset.fiscal_years(count: roes.size)
    years.each_with_index do |y, i|
      fr = FinancialReport.create!(stock: stock, report_date: Date.new(y, 10, 31),
                                   report_type: "US_ANNUAL", market: "US",
                                   period_type: "annual", currency: "USD")
      FinancialIndicator.create!(financial_report: fr, stock: stock,
                                 report_date: Date.new(y, 10, 31), market: "US",
                                 period_type: "annual", roe_avg: roes[i])
      CashFlow.create!(financial_report: fr, stock: stock,
                       report_date: Date.new(y, 10, 31), market: "US",
                       period_type: "annual",
                       operating_cash_flow: ocfs ? ocfs[i] : 100_000_000)
    end
  end

  # 财务库喂数：近 N 个完整财年年报 ROE 与经营现金流（N=roes.size，三维筛选的数据源）
  def ww_give_financials(site_symbol, roes:, ocfs: nil)
    stock = Stock.find_by!(symbol: site_symbol)
    years = WindowWatch::FinancialPreset.fiscal_years(count: roes.size)
    years.each_with_index do |y, i|
      fr = FinancialReport.create!(stock: stock, report_date: Date.new(y, 12, 31),
                                   report_type: "CN_ANNUAL", market: "CN",
                                   period_type: "annual", currency: "CNY")
      FinancialIndicator.create!(financial_report: fr, stock: stock,
                                 report_date: Date.new(y, 12, 31), market: "CN",
                                 period_type: "annual", roe_avg: roes[i])
      CashFlow.create!(financial_report: fr, stock: stock,
                       report_date: Date.new(y, 12, 31), market: "CN",
                       period_type: "annual",
                       operating_cash_flow: ocfs ? ocfs[i] : 100_000_000)
    end
  end

  # 快照 JSON：stats/universe 由 rows 自动推导，保证默认 payload 必过校验
  # in_position: true → v1.2 五键结构（tiers.IN_POSITION 逐股明细 + in_position_count 对账）
  # market: "US" → 契约 v0.8 US 包（universe 单键 exchanges、US 免责文案、US fixture 默认行）
  def ww_payload(month: "2026-10", rows: nil, trade_date: "2026-11-04", is_stale: false, in_position: false, market: "CN")
    rows ||= market == "US" ? WW_US_STOCKS : WW_STOCKS
    ip_rows = in_position ? (market == "US" ? WW_US_IN_POSITION : WW_IN_POSITION) : []
    all_rows = rows + ip_rows
    tc = Hash.new(0)
    rows.each { |r| tc[r[:tier]] += 1 }
    exchanges = if market == "US"
                  { "US" => all_rows.size }
                else
                  { "SH" => all_rows.count { |r| r[:exchange] == "SH" },
                    "SZ" => all_rows.count { |r| r[:exchange] == "SZ" },
                    "BJ" => all_rows.count { |r| r[:exchange] == "BJ" } }
                end
    {
      "snapshot_version" => in_position ? "1.2" : "1.1",
      "month" => month,
      "generated_at" => "2026-11-05T09:30:00+08:00",
      "caliber_version" => "v1.10",
      "script_version" => "1.0.0",
      "data_snapshot" => { "trade_date" => trade_date, "fetched_at" => "2026-11-05T09:00:00+08:00",
                           "adjust" => "forward", "source" => market == "US" ? "yahoo" : "sina/eastmoney", "last_month_closed" => month,
                           "is_stale" => is_stale, "stale_days" => is_stale ? 3 : 0, "stale_trading_days" => is_stale ? 3 : 0 },
      "universe" => { "market" => market, "count" => all_rows.size, "exchanges" => exchanges },
      "tiers" => { "T1" => [], "T2_P2" => [], "T2_P1" => [], "T3" => [] }.tap { |t| t["IN_POSITION"] = [] if in_position },
      "stats" => { "tier_counts" => { "T1" => tc["T1"], "T2_P2" => tc["T2_P2"], "T2_P1" => tc["T2_P1"], "T3" => tc["T3"] },
                   "in_position_count" => ip_rows.size },
      "disclaimer" => market == "US" ? WW_US_DISCLAIMER : WW_DISCLAIMER
    }.tap do |p|
      all_rows.each { |r| p["tiers"][r[:tier].to_s] << r.transform_keys(&:to_s) }
    end
  end
end
