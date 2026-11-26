require "test_helper"
require_relative "../../support/window_watch_snapshot_helper"

# ingest 服务层（契约 v0.4.0 §三/§四）：字段逐位回读、财务字段拦截、latest、防御性校验
class WindowWatch::SnapshotIngestTest < ActiveSupport::TestCase
  include WindowWatchSnapshotHelper

  setup { ww_create_stocks! }

  def ingest(payload = ww_payload)
    WindowWatch::SnapshotIngest.call(payload: payload, source_ip: "127.0.0.1")
  end

  test "合法包落库：逐股字段逐位回读（6 位小数精度，契约 Q3）" do
    snapshot, errors = ingest
    assert_empty errors
    row = snapshot.stocks.find_by(symbol: "601985.SH")
    assert_equal BigDecimal("1.234567"), row.hist
    assert_equal BigDecimal("0.765432"), row.prev_hist
    assert_equal BigDecimal("1.250001"), row.ratio
    assert_equal "T1", row.tier
    assert_equal "2026-08", row.open_month
    assert_equal 3, row.months_since_open
    assert_equal 7, row.sa_run
    assert_equal "sh601985", row.code
  end

  test "ActionController::Parameters 输入（真实请求路径）同样通过" do
    wrapped = ActionController::Parameters.new(ww_payload).permit!
    snapshot, errors = ingest(wrapped)
    assert_empty errors
    assert_equal 6, snapshot.stocks.count
  end

  test "v0.4.0 拦截：逐股行携带财务字段 422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["roe"] = 16.8
    payload["tiers"]["T2_P2"][0]["run3_asof"] = true
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "不得携带财务字段", errors.join
    assert_match "roe", errors.join
    assert_match "run3_asof", errors.join
  end

  test "v0.4.0 拦截：stats 携带财务统计键 422" do
    payload = ww_payload
    payload["stats"]["main_group_run3"] = 36
    payload["stats"]["finance_count"] = 42
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "不得携带财务统计键", errors.join
    assert_match "main_group_run3", errors.join
  end

  # v0.7 fixture：北交所同权入档的 BJ 行（symbol 键形态，供 ww_payload rows 参数消费）
  WW_BJ_ROW = { symbol: "920001.BJ", code: "bj920001", name: "测试北股", industry: "电子", exchange: "BJ",
                tier: "T1", subtag: "", hist: "0.100000", prev_hist: "0.050000",
                dif: "0.080000", dea: "0.060000", ratio: "1.333333",
                open_month: "2026-09", months_since_open: 2, last_close_month: nil, sa_run: 3 }.freeze

  test "v0.7：BJ 行入 tiers 正常落库（exchange 枚举扩 BJ、bj_count 退役）" do
    Stock.create!(symbol: "BJ920001", name: "测试北股", market: "CN", exchange: "BJSE",
                  industry: "电子", status: "active")
    snapshot, errors = ingest(ww_payload(rows: WW_STOCKS + [WW_BJ_ROW]))
    assert_empty errors
    row = snapshot.stocks.find_by(symbol: "920001.BJ")
    assert_equal "BJ", row.exchange
    assert_equal "bj920001", row.code
    assert_equal "T1", row.tier
  end

  test "v0.7：exchange 枚举外（HK）仍 422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["exchange"] = "HK"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "exchange 非法", errors.join
  end

  test "v0.7：BJ exchange 与 code 前缀不一致 422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["exchange"] = "BJ"
    payload["tiers"]["T1"][0]["code"] = "sh601985"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "与 code 前缀", errors.join
  end

  test "symbol/code 互不一致（格式非法）422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["code"] = "sz000001"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "互不一致", errors.join
  end

  test "大写 code 落库归一为小写，财务预设过滤不受影响（评审修复1）" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["code"] = "SH601985"
    snapshot, errors = ingest(payload)
    assert_empty errors
    assert_equal "sh601985", snapshot.stocks.find_by(symbol: "601985.SH").code
  end

  test "latest 返回判定月最大的成功快照" do
    ingest(ww_payload(month: "2026-09", trade_date: "2026-10-09"))
    ingest(ww_payload(month: "2026-10"))
    assert_equal "2026-10", WindowWatchSnapshot.latest.month
  end

  # ---- 契约 v0.5（snapshot 1.2）IN_POSITION 兼容校验（05 变更单 §二）----

  test "v1.2 合法包落库：IN_POSITION 行字段逐位回读，入场月晚于判定月不拒（口径②）" do
    snapshot, errors = ingest(ww_payload(in_position: true))
    assert_empty errors
    assert_equal "1.2", snapshot.snapshot_version
    assert_equal 8, snapshot.stocks.count
    row = snapshot.stocks.find_by!(symbol: "601318.SH")
    assert_equal "IN_POSITION", row.tier
    assert_equal "2025-06", row.entry_month
    assert_equal 16, row.months_in_position
    # 泸州老窖 entry_month=2026-11 晚于判定月 2026-10：实测正常形态，必须照常入库
    assert_equal "2026-11", snapshot.stocks.find_by!(symbol: "000568.SZ").entry_month
  end

  test "v1.1 四键包仍接受（IN_POSITION 可选键，平滑过渡）" do
    snapshot, errors = ingest(ww_payload)
    assert_empty errors
    assert_equal 6, snapshot.stocks.count
  end

  test "entry_month 格式非法 422（仅验格式，不做语义上限校验）" do
    payload = ww_payload(in_position: true)
    payload["tiers"]["IN_POSITION"][0]["entry_month"] = "2025/06"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "entry_month", errors.join
  end

  test "months_in_position 非 ≥1 整数 422" do
    payload = ww_payload(in_position: true)
    payload["tiers"]["IN_POSITION"][0]["months_in_position"] = 0
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "months_in_position", errors.join
  end

  test "IN_POSITION 行 subtag 非空 422（恒空约束）" do
    payload = ww_payload(in_position: true)
    payload["tiers"]["IN_POSITION"][0]["subtag"] = "continuation"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "subtag 须为空", errors.join
  end

  test "in_position_count 与 IN_POSITION 行数不一致 422（v1.2 对账）" do
    payload = ww_payload(in_position: true)
    payload["stats"]["in_position_count"] = 99
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "in_position_count=99", errors.join
  end

  test "IN_POSITION 与四档 symbol 交集非空 422（互斥=全局去重）" do
    payload = ww_payload(in_position: true)
    payload["tiers"]["IN_POSITION"] << payload["tiers"]["T1"][0].dup
    payload["stats"]["in_position_count"] = 3
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "symbol 重复", errors.join
  end

  # ---- 契约 v0.8（美股市场化）：US 包校验分支 + (market, month) 双键幂等 ----

  test "v0.8 US 合法包落库：market 入头、code 归一小写、BRK.A 带点码逐位回读" do
    ww_create_us_stocks!
    snapshot, errors = ingest(ww_payload(market: "US", in_position: true))
    assert_empty errors
    assert_equal "US", snapshot.market
    row = snapshot.stocks.find_by(symbol: "BRK.A.US")
    assert_equal "brk.a", row.code
    assert_equal "US", row.exchange
    assert_equal BigDecimal("0.456789"), row.hist
    assert_equal "continuation", row.subtag
    assert_equal "IN_POSITION", snapshot.stocks.find_by(symbol: "AAPL.US").tier
    assert_equal "US", WindowWatchIngestLog.order(:id).last.market
  end

  test "v0.8 同月 CN/US 双包共存互不覆盖（幂等键=(market, month)）" do
    ww_create_us_stocks!
    cn, e1 = ingest(ww_payload)
    us, e2 = ingest(ww_payload(market: "US"))
    assert_empty e1 + e2
    assert_equal 2, WindowWatchSnapshot.where(month: "2026-10").count
    assert_equal 6, cn.reload.stocks.count
    assert_equal 4, us.reload.stocks.count
    assert_equal "CN", WindowWatchSnapshot.latest(market: "CN").market
    assert_equal "US", WindowWatchSnapshot.latest(market: "US").market
  end

  test "v0.8 同 (month, market) 重推=整包覆盖，另一市场包不受影响" do
    ww_create_us_stocks!
    ingest(ww_payload)
    ingest(ww_payload(market: "US"))
    smaller = ww_payload(market: "US")
    smaller["tiers"]["T3"] = []
    smaller["universe"]["count"] = 3
    smaller["universe"]["exchanges"] = { "US" => 3 }
    smaller["stats"]["tier_counts"]["T3"] = 0
    snapshot, errors = ingest(smaller)
    assert_empty errors
    assert_equal 1, WindowWatchSnapshot.where(month: "2026-10", market: "US").count
    assert_equal 3, snapshot.stocks.count
    assert_equal 6, WindowWatchSnapshot.where(month: "2026-10", market: "CN").first.stocks.count
  end

  test "v0.8 US symbol 仅 endsWith .US 但拼接不一致 422（整串拼接校验，非后缀匹配）" do
    ww_create_us_stocks!
    payload = ww_payload(market: "US")
    payload["tiers"]["T1"][0]["symbol"] = "X.NVDA.US"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match 'symbol 须为 code+".US"', errors.join
  end

  test "v0.8 US exchange 非 US 422" do
    ww_create_us_stocks!
    payload = ww_payload(market: "US")
    payload["tiers"]["T1"][0]["exchange"] = "NASDAQ"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "exchange 非法（US 包恒 US）", errors.join
  end

  test "v0.8 US code 小写/格式非法 422（须大写 Yahoo 码）" do
    ww_create_us_stocks!
    payload = ww_payload(market: "US")
    payload["tiers"]["T1"][0]["code"] = "nvda"
    payload["tiers"]["T1"][0]["symbol"] = "nvda.US"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "code 格式非法", errors.join
  end

  test "v0.8 universe.market 枚举外（HK）422（港股封存不上，契约 v0.8 §一）" do
    payload = ww_payload
    payload["universe"]["market"] = "HK"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "universe.market 非法", errors.join
    # 评审修复1：market 非法即止，不叠加 CN 分支逐股/命中噪音
    assert_equal 1, errors.size
  end

  test "v0.8 US 包 exchanges 小写键 422 报单键错误而非误导性上限（评审修复3）" do
    ww_create_us_stocks!
    payload = ww_payload(market: "US")
    payload["universe"]["exchanges"] = { "us" => payload["universe"]["count"] }
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "仅允许 US 单键", errors.join
    refute_match "超过 universe.exchanges.US", errors.join
  end

  test "v0.8 US 包 exchanges 多键 422（仅允许 US 单键）" do
    ww_create_us_stocks!
    payload = ww_payload(market: "US")
    payload["universe"]["exchanges"] = { "US" => 3, "NASDAQ" => 1 }
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "仅允许 US 单键", errors.join
  end

  test "v0.8 US code 未命中 stocks 表 422 并列出未命中清单" do
    ww_create_us_stocks!
    Stock.where(market: "US", symbol: "UBER").delete_all
    payload = ww_payload(market: "US")
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "未命中网站股票库", errors.join
    assert_match "UBER", errors.join
  end

  test "v0.8 带点码命中双向归一：库内斜杠形态 BRK/A 互认 Yahoo 点码 BRK.A（2026-11-26 DSH 422 修复）" do
    ww_create_us_stocks!
    Stock.find_by!(symbol: "BRK.A", market: "US").update_column(:symbol, "BRK/A") # 模拟迁移前/漂移形态
    snapshot, errors = ingest(ww_payload(market: "US"))
    assert_empty errors
    assert_equal "brk.a", snapshot.stocks.find_by(symbol: "BRK.A.US").code # 快照 code 恒 Yahoo 底座码，不随库形态变
  end

  test "v0.8 CN 包校验路径零变化：US 行混入 CN 包仍按 SH/SZ/BJ 枚举 422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["symbol"] = "NVDA.US"
    payload["tiers"]["T1"][0]["code"] = "NVDA"
    payload["tiers"]["T1"][0]["exchange"] = "US"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "exchange 非法（tiers 内仅 SH/SZ/BJ）", errors.join
  end
end
