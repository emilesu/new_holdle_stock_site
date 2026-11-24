require "test_helper"
require_relative "../../support/window_watch_snapshot_helper"

# ingest 服务层（契约 §三/§四）：字段逐位回读、null 语义、latest、防御性校验
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
    assert_equal true, row.run3_asof
    assert_equal "sh601985", row.code
  end

  test "run3_asof/roe 的 null 语义保留（无财报 ≠ false）" do
    rows = WW_STOCKS.map(&:dup)
    rows[3][:run3_asof] = nil
    rows[3][:roe] = nil
    snapshot, errors = ingest(ww_payload(rows: rows))
    assert_empty errors
    assert_nil snapshot.stocks.find_by(symbol: "000858.SZ").run3_asof
    assert_nil snapshot.stocks.find_by(symbol: "000858.SZ").roe
  end

  test "ActionController::Parameters 输入（真实请求路径）同样通过" do
    wrapped = ActionController::Parameters.new(ww_payload).permit!
    snapshot, errors = ingest(wrapped)
    assert_empty errors
    assert_equal 6, snapshot.stocks.count
  end

  test "main_group_run5 与逐股行不一致 422" do
    payload = ww_payload
    payload["stats"]["main_group_run5"] = 99
    snapshot, errors = ingest(payload)
    assert_nil snapshot
    assert_match "main_group_run5", errors.join
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
