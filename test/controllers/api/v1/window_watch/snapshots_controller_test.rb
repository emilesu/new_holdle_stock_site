require "test_helper"
require_relative "../../../../support/window_watch_snapshot_helper"

# 开窗快照 ingest API（契约 02 v0.3 §四）：鉴权 fail-closed / 校验 422 全拒 / 幂等覆盖 / 审计
class Api::V1::WindowWatch::SnapshotsControllerTest < ActionDispatch::IntegrationTest
  include WindowWatchSnapshotHelper

  setup do
    ENV["HOLDLE_WINDOW_TOKEN"] = "window-test-token"
    @auth = { "Authorization" => "Bearer window-test-token" }
    ww_create_stocks!
  end

  teardown { ENV.delete("HOLDLE_WINDOW_TOKEN") }

  def post_snapshot(payload = ww_payload, headers: @auth)
    post "/api/v1/window_watch/snapshots", params: payload, as: :json, headers: headers
  end

  # ---- 鉴权 ----

  test "无 token / 错误 token / ENV 未配置均 401（fail-closed）" do
    post_snapshot(ww_payload, headers: {})
    assert_response 401
    post_snapshot(ww_payload, headers: { "Authorization" => "Bearer wrong" })
    assert_response 401
    ENV["HOLDLE_WINDOW_TOKEN"] = ""
    post_snapshot(ww_payload)
    assert_response 401
  end

  # ---- 成功路径 ----

  test "合法快照 201：落库主表+行表并写审计日志" do
    post_snapshot
    assert_response 201
    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal "2026-10", body["month"]
    assert_equal({ "T1" => 2, "T2_P2" => 2, "T2_P1" => 1, "T3" => 1 }, body["counts"])

    snapshot = WindowWatchSnapshot.find_by(month: "2026-10")
    assert_equal 6, snapshot.stocks.count
    assert_equal WW_DISCLAIMER, snapshot.disclaimer
    log = WindowWatchIngestLog.last
    assert_equal "ok", log.result
    assert_equal "2026-10", log.snapshot_month
  end

  # ---- 校验 422（任一失败全量拒绝，不落半包）----

  test "month 格式非法 422" do
    post_snapshot(ww_payload.tap { |p| p["month"] = "202610" })
    assert_response 422
    assert_match "month", response.parsed_body["errors"].join
  end

  test "tier_counts 与 tiers 实际条数不一致 422 且库内无残留" do
    payload = ww_payload
    payload["stats"]["tier_counts"]["T1"] = 99
    post_snapshot(payload)
    assert_response 422
    assert_equal 0, WindowWatchSnapshot.count
    assert_equal "rejected", WindowWatchIngestLog.last.result
  end

  test "stats 出现 null（bj_count）422" do
    payload = ww_payload
    payload["stats"]["bj_count"] = nil
    post_snapshot(payload)
    assert_response 422
    assert_match "bj_count", response.parsed_body["errors"].join
  end

  test "缺 in_position_count（v0.3.3 起恒在键）422" do
    payload = ww_payload
    payload["stats"].delete("in_position_count")
    post_snapshot(payload)
    assert_response 422
    assert_match "in_position_count", response.parsed_body["errors"].join
  end

  test "symbol 重复 422" do
    payload = ww_payload
    payload["tiers"]["T1"] << payload["tiers"]["T1"].first.dup
    post_snapshot(payload)
    assert_response 422
    assert_match "601985.SH", response.parsed_body["errors"].join
  end

  test "未知 code 422 且逐个列出未命中 code（纪要决议3）" do
    payload = ww_payload
    row = WW_STOCKS.first.transform_keys(&:to_s).merge("symbol" => "999999.SH", "code" => "sh999999", "name" => "不存在的股票")
    payload["tiers"]["T1"] << row
    payload["stats"]["tier_counts"]["T1"] += 1
    post_snapshot(payload)
    assert_response 422
    assert_match "SH999999", response.parsed_body["errors"].join
  end

  test "exchange 与 code 前缀不一致 422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["exchange"] = "SZ"
    post_snapshot(payload)
    assert_response 422
    assert_match "前缀", response.parsed_body["errors"].join
  end

  test "universe.exchanges 之和 ≠ count 422" do
    payload = ww_payload
    payload["universe"]["exchanges"]["SH"] = 10
    post_snapshot(payload)
    assert_response 422
    assert_match "universe", response.parsed_body["errors"].join
  end

  test "行内 tier 字段与所在档数组键不一致 422（评审修复1）" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["tier"] = "T3"
    post_snapshot(payload)
    assert_response 422
    assert_match "与所在档数组键", response.parsed_body["errors"].join
  end

  test "subtag 非法值 422" do
    payload = ww_payload
    payload["tiers"]["T1"][0]["subtag"] = "whatever"
    post_snapshot(payload)
    assert_response 422
    assert_match "subtag", response.parsed_body["errors"].join
  end

  # ---- 幂等（V9）----

  test "同月重推整包覆盖：行数与头字段跟随新包，不重复不丢失" do
    post_snapshot
    new_rows = WW_STOCKS.reject { |r| r[:name] == "五粮液" }
    post_snapshot(ww_payload(rows: new_rows))
    assert_response 201

    assert_equal 1, WindowWatchSnapshot.where(month: "2026-10").count
    snapshot = WindowWatchSnapshot.find_by(month: "2026-10")
    assert_equal 5, snapshot.stocks.count
    assert_nil snapshot.stocks.find_by(name: "五粮液")
    assert_equal 1, snapshot.stats["tier_counts"]["T2_P2"] # 新包 stats 已同步
  end

  test "跨月新快照=新记录，latest 取判定月最大" do
    post_snapshot(ww_payload(month: "2026-09", trade_date: "2026-10-09"))
    assert_response 201
    post_snapshot(ww_payload(month: "2026-10"))
    assert_response 201
    assert_equal 2, WindowWatchSnapshot.count
    assert_equal "2026-10", WindowWatchSnapshot.latest.month
  end
end
