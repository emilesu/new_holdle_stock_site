require "test_helper"
require_relative "../../support/window_watch_snapshot_helper"

# R2③ sparkline 服务：近 6 月柱值装配 + 末根柱对账条款（契约 v0.5 §四备案）
class WindowWatchMonthlySparklineTest < ActiveSupport::TestCase
  include WindowWatchSnapshotHelper

  setup do
    ww_create_stocks!
    @snapshot, errors = WindowWatch::SnapshotIngest.call(payload: ww_payload, source_ip: "127.0.0.1")
    assert_empty errors
    @row = @snapshot.stocks.find_by!(code: "sh601985")
    @stock = Stock.find_by!(symbol: "SH601985")
  end

  test "末根柱恒取快照 hist（对账条款），其余取月K库递推值" do
    give_bars(%w[2026-05 2026-06 2026-07 2026-08 2026-09 2026-10])
    res = spark
    assert_equal 6, res.values.size
    assert_in_delta @row.hist.to_f, res.values.last, 1e-9
    refute_predicate res, :lagged
    refute_nil res.values[4] # 2026-09 由库内递推
  end

  test "库缺判定月：lagged=true、cutoff=库内最新月，末柱仍以快照补" do
    give_bars(%w[2026-05 2026-06 2026-07 2026-08 2026-09])
    res = spark
    assert_predicate res, :lagged
    assert_equal "2026-09", res.cutoff
    assert_in_delta @row.hist.to_f, res.values.last, 1e-9
  end

  test "库完全无数据：末两柱回落快照 hist/prev_hist，更早槽位为 nil" do
    res = spark
    assert_predicate res, :lagged
    assert_nil res.cutoff
    assert_in_delta @row.prev_hist.to_f, res.values[-2], 1e-9
    assert_in_delta @row.hist.to_f, res.values[-1], 1e-9
    assert_nil res.values[-3]
  end

  test "快照月格式非法时返回空集（视图层回落双柱组件）" do
    assert_empty WindowWatch::MonthlySparkline.call([@row], snapshot_month: "2026-13")
  end

  private

  def spark
    WindowWatch::MonthlySparkline.call([@row], snapshot_month: @snapshot.month)["sh601985"]
  end

  def give_bars(months)
    months.each_with_index do |m, i|
      y, mo = m.split("-").map(&:to_i)
      @stock.stock_monthly_bars.create!(market: "CN", trade_date: Date.new(y, mo, -1),
                                        hfq_close: 10 + i, hfq_factor: 1)
    end
  end
end
