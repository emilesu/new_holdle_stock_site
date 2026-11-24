# 开窗快照测试支撑：6 只合成股票覆盖四档/subtag/金融/质量字段；数值刻意取 6 位小数长尾形态，
# 便于 V11 断言「绝对数值未渲染」（两位小数形态也逐一检查，见 redline 测试）
module WindowWatchSnapshotHelper
  WW_DISCLAIMER = "本页面为按 HOLDLE 方法论对股票月K状态的客观描述，不构成投资建议，不构成任何买卖推荐。方法论基于历史规律总结，过去的状态表现不代表未来。数据截至 2026-10 月K收盘，价格按前复权口径，除权后历史价格会变动；页面不包含盘中实时行情。请独立判断并自行承担决策责任。"

  WW_STOCKS = [
    { symbol: "601985.SH", code: "sh601985", name: "中国核电", industry: "电力", exchange: "SH",
      tier: "T1", subtag: "", finance: false, st: false, run3_asof: true, run5_asof: true,
      roe: 16.8, roe_band: "15-20", hist: "1.234567", prev_hist: "0.765432",
      dif: "1.555555", dea: "0.987654", ratio: "1.250001",
      open_month: "2026-08", months_since_open: 3, last_close_month: nil, sa_run: 7 },
    { symbol: "600036.SH", code: "sh600036", name: "招商银行", industry: "银行", exchange: "SH",
      tier: "T1", subtag: "", finance: true, st: false, run3_asof: true, run5_asof: true,
      roe: 18.2, roe_band: "15-20", hist: "2.345678", prev_hist: "1.876543",
      dif: "2.111111", dea: "1.444444", ratio: "1.623457",
      open_month: "2026-10", months_since_open: 1, last_close_month: nil, sa_run: 9 },
    { symbol: "000333.SZ", code: "sz000333", name: "美的集团", industry: "家电", exchange: "SZ",
      tier: "T2_P2", subtag: "continuation", finance: false, st: false, run3_asof: true, run5_asof: false,
      roe: 22.5, roe_band: "20+", hist: "0.555555", prev_hist: "0.888888",
      dif: "0.666666", dea: "0.444444", ratio: "1.250002",
      open_month: nil, months_since_open: nil, last_close_month: "2026-09", sa_run: 4 },
    { symbol: "000858.SZ", code: "sz000858", name: "五粮液", industry: "白酒", exchange: "SZ",
      tier: "T2_P2", subtag: "sticky_micro", finance: false, st: false, run3_asof: false, run5_asof: false,
      roe: 25.1, roe_band: "20+", hist: "0.001234", prev_hist: "0.023456",
      dif: "0.015555", dea: "0.041111", ratio: "0.024999",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 2 },
    { symbol: "600519.SH", code: "sh600519", name: "贵州茅台", industry: "白酒", exchange: "SH",
      tier: "T2_P1", subtag: "", finance: false, st: false, run3_asof: true, run5_asof: true,
      roe: 31.4, roe_band: "30+", hist: "-0.345678", prev_hist: "-0.654321",
      dif: "0.555555", dea: "0.722222", ratio: "0.478630",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 3 },
    { symbol: "300750.SZ", code: "sz300750", name: "宁德时代", industry: "电池", exchange: "SZ",
      tier: "T3", subtag: "high_gate", finance: false, st: false, run3_asof: true, run5_asof: false,
      roe: 24.6, roe_band: "20+", hist: "3.456789", prev_hist: "2.987654",
      dif: "2.555555", dea: "1.876543", ratio: "1.842087",
      open_month: nil, months_since_open: nil, last_close_month: nil, sa_run: 12 }
  ].freeze

  # 站内 stocks 表落库（code 命中校验用；symbol 为站内 SH601985 格式）
  def ww_create_stocks!
    WW_STOCKS.each do |r|
      code, ex = r[:symbol].split(".")
      Stock.create!(symbol: "#{ex}#{code}", name: r[:name], market: "CN",
                    exchange: "#{ex}SE", industry: r[:industry], status: "active")
    end
  end

  # 快照 JSON：stats 由 rows 自动推导，保证默认 payload 必过校验；测试改 rows/字段制造 422
  def ww_payload(month: "2026-10", rows: nil, trade_date: "2026-11-04", is_stale: false)
    rows ||= WW_STOCKS
    tc = Hash.new(0)
    rows.each { |r| tc[r[:tier]] += 1 }
    {
      "snapshot_version" => "1.0",
      "month" => month,
      "generated_at" => "2026-11-05T09:30:00+08:00",
      "caliber_version" => "v1.10",
      "script_version" => "0.2.0",
      "data_snapshot" => { "trade_date" => trade_date, "fetched_at" => "2026-11-05T09:00:00+08:00",
                           "adjust" => "forward", "source" => "sina/yahoo", "last_month_closed" => month,
                           "is_stale" => is_stale, "stale_days" => is_stale ? 3 : 0, "stale_trading_days" => is_stale ? 3 : 0 },
      "universe" => { "market" => "CN", "count" => 6, "exchanges" => { "SH" => 3, "SZ" => 3, "BJ" => 0 } },
      "tiers" => { "T1" => [], "T2_P2" => [], "T2_P1" => [], "T3" => [] },
      "stats" => { "tier_counts" => { "T1" => tc["T1"], "T2_P2" => tc["T2_P2"], "T2_P1" => tc["T2_P1"], "T3" => tc["T3"] },
                   "main_group_run3" => rows.count { |r| r[:run3_asof] == true },
                   "main_group_run5" => rows.count { |r| r[:run5_asof] == true },
                   "finance_count" => rows.count { |r| r[:finance] == true },
                   "st_count" => rows.count { |r| r[:st] == true },
                   "bj_count" => 0 },
      "disclaimer" => WW_DISCLAIMER
    }.tap do |p|
      rows.each { |r| p["tiers"][r[:tier].to_s] << r.transform_keys(&:to_s) }
    end
  end
end
