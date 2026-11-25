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

  test "bj_count 为 null 422（stats 必填键）" do
    payload = ww_payload
    payload["stats"]["bj_count"] = nil
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "bj_count", errors.join
  end

  test "tiers 内混入 BJ 422（北交所单列不入列）" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["exchange"] = "BJ"
    payload["tiers"]["T1"][0]["code"] = "bj830799"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "BJ", errors.join
  end

  test "symbol/code 互不一致（格式非法）422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["code"] = "sz000001"
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "互不一致", errors.join
  end

  test "latest 返回判定月最大的成功快照" do
    ingest(ww_payload(month: "2026-09", trade_date: "2026-10-09"))
    ingest(ww_payload(month: "2026-10"))
    assert_equal "2026-10", WindowWatchSnapshot.latest.month
  end
end
