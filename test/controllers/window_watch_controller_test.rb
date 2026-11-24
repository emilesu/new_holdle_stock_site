require "test_helper"
require_relative "../support/window_watch_snapshot_helper"

# /window-watch 页面（需求单 01 v0.3）：访问控制 / 主组与全量视图 / R4 空态分支 / 警示与免责
class WindowWatchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include WindowWatchSnapshotHelper

  setup do
    ww_create_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload, source_ip: "127.0.0.1")
  end

  # ---- §一 访问控制（暗发布期：DARK_RELEASE=true，非管理员一律重定向首页）----

  test "暗发布：未登录访问重定向首页，不暴露功能存在" do
    get window_watch_path
    assert_redirected_to root_path
  end

  test "暗发布：普通会员与普通用户均重定向，仅管理员可见" do
    member = User.create!(email: "ww-member@test.local", password: "WwMember2026!", nickname: "开窗会员账号",
                          role: "member", member_expire_at: 1.year.from_now,
                          confirmed_at: Time.current, onboarded_at: Time.current)
    sign_in member
    get window_watch_path
    assert_redirected_to root_path

    sign_in users(:one)
    get window_watch_path
    assert_redirected_to root_path
  end

  test "管理员：完整页面含主组行与全量入口" do
    sign_in users(:two) # admin fixture
    get window_watch_path
    assert_includes response.body, "中国核电"
    assert_includes response.body, "贵州茅台"
    assert_includes response.body, "全部股票"
  end

  # ---- 主组视图（§3.3 默认：仅 run3_asof=true）----

  test "主组视图只显示质量达标股票（V2：条数=main_group_run3）" do
    sign_in users(:two)
    get window_watch_path
    body = response.body
    assert_includes body, "中国核电"
    refute_includes body, "五粮液" # run3_asof=false 不进主组
    # 主组 5 只（6 - 五粮液）
    assert_equal 5, WindowWatchSnapshot.latest.stocks.where(run3_asof: true).count
  end

  test "T3 档 subtag 行尾注与折叠呈现（§3.2）" do
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "柱已爬至两线上方，按规则高位不开窗"
    assert_includes response.body, "宁德时代"
  end

  # ---- 全量视图 ----

  test "全量视图含全部行与固定提示行；档筛选/行业筛选/排序生效" do
    sign_in users(:two)
    get window_watch_path(view: "all")
    assert_includes response.body, "默认视图只显示质量达标股票；本视图为全量技术形态列表，未含企业质量筛选"
    assert_includes response.body, "五粮液"
    assert_equal 6, WindowWatchSnapshot.latest.stocks.count

    get window_watch_path(view: "all", tier: "T1")
    assert_includes response.body, "中国核电"
    refute_includes response.body, "贵州茅台"

    get window_watch_path(view: "all", industry: "白酒")
    assert_includes response.body, "五粮液"
    assert_includes response.body, "贵州茅台"
    refute_includes response.body, "中国核电"

    get window_watch_path(view: "all", sort: "sa_run_desc")
    assert_response :success
    # 非法 sort 参数回落默认排序（白名单 A6）
    get window_watch_path(view: "all", sort: "DROP TABLE")
    assert_response :success
  end

  test "全量视图某档 0 只：空态文案（R4）" do
    sign_in users(:two)
    WindowWatchSnapshotStock.where(tier: "T3").delete_all
    get window_watch_path(view: "all", tier: "T3")
    assert_includes response.body, "本月状态A·暂不开窗暂无股票"
  end

  # ---- R4 空态分支 ----

  test "冷启动：库内无快照时固定文案，无个股区块" do
    WindowWatchSnapshot.destroy_all
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "数据正在准备，首个快照尚未生成"
    refute_includes response.body, "中国核电"
  end

  test "最新判定月缺失：提示并照常渲染上一月（R4）" do
    WindowWatchSnapshot.destroy_all
    WindowWatch::SnapshotIngest.call(payload: ww_payload(month: "2026-09", trade_date: "2026-10-09"), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "本月数据尚未更新，最近一次更新：2026-09 月K收盘"
    assert_includes response.body, "中国核电" # 列表照常渲染
  end

  test "is_stale=true：警示条出现（V4）" do
    WindowWatch::SnapshotIngest.call(payload: ww_payload(month: "2026-11", trade_date: "2026-11-20", is_stale: true), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "注意：本次数据更新滞后（数据截至 2026-11-20），判定可能未包含最近交易日行情。"
    # §五.2 升级为警示条=替换常态横幅，不得双显示（评审修复4）
    refute_includes response.body, "每月更新一次，月中不刷新"
  end

  # ---- R7/V5 免责逐字 ----

  test "免责声明与快照字段逐字一致" do
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, WindowWatchSnapshotHelper::WW_DISCLAIMER
  end
end
