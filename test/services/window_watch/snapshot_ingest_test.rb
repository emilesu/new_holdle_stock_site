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
end
