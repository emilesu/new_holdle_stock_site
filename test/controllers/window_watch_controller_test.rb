require "test_helper"
require_relative "../support/window_watch_snapshot_helper"

# /window-watch 页面（需求单 01 v0.3）：访问控制 / 主组与全量视图 / R4 空态分支 / 警示与免责
class WindowWatchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include WindowWatchSnapshotHelper

  setup do
    ww_create_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload, source_ip: "127.0.0.1")
    # 财务库喂数（页面侧预设数据源）：核电/招行/茅台/宁德 三年 ROE≥15；美的 ROE 12 档（仅 10%+ 命中）；五粮液无财务数据（join 兜底）
    ww_give_financials("SH601985", roes: [16, 17, 18])
    ww_give_financials("SH600036", roes: [18, 19, 20])
    ww_give_financials("SH600519", roes: [30, 31, 32])
    ww_give_financials("SZ300750", roes: [24, 25, 26])
    ww_give_financials("SZ000333", roes: [12, 13, 14])
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

  # ---- 财务预设视图（需求单 v0.3.0：页面侧筛选，近3财年 ROE≥档 且 经营现金流>0；R1 默认档=10%）----

  test "预设 15%+：命中行显示，未命中与无财务行不显示（V2=财务库命中数）" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    body = response.body
    assert_includes body, "中国核电"
    assert_includes body, "贵州茅台"
    refute_includes body, "美的集团"   # ROE 12-14，不达 15% 档
    refute_includes body, "五粮液"     # 财务库未覆盖，join 兜底=不进预设（全量视图仍显示）
    assert_equal 4, WindowWatch::FinancialPreset.hit_symbols(band: 15).size
  end

  test "R1 默认档位 10%：美的集团进入默认视图；非法档位回落 10" do
    sign_in users(:two)
    get window_watch_path # 默认档=10（R1 改）
    assert_includes response.body, "美的集团"
    get window_watch_path(view: "main", band: 99) # 非法回落默认 10
    assert_includes response.body, "美的集团"
  end

  test "R1 预设视图按金字塔综合分降序（同分贴0轴比值优先），不再按开窗月" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    # T1 块：招行 85 分 > 核电 70 分（旧 open_month 排序同为招行在前，故用 ②/③ 块交叉验证分数序）
    body = response.body
    t1_seg = body[/<section id="ww-t1".*?<\/section>/m].to_s
    assert_operator t1_seg.index("招商银行"), :<, t1_seg.index("中国核电"), "T1 块金字塔序"
    # ②红柱收敛块：美的(60) 命中 10% 档；③暂不开窗块：宁德(50)
    get window_watch_path(view: "main", band: 10)
    t2_seg = response.body[/<section id="ww-t2p2".*?<\/section>/m].to_s
    assert_includes t2_seg, "美的集团"
  end

  test "卡片行财务标注来自财务库 join（ROE 小字），无「质量达标」表述" do
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "ROE 18.0%" # 中国核电最新年报 roe_avg=18
    refute_includes response.body, "质量达标"
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
    assert_includes response.body, "财务预设视图按财务指标筛选（财务库）；本视图为全量技术形态列表，未含财务指标筛选"
    assert_includes response.body, "五粮液" # 全量视图含财务未覆盖行（join 兜底照常展示）
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

  # ---- R2 月份切换与全量检索 ----

  test "R2 月份切换：指定历史月渲染该快照，非法/不存在月份回落 latest" do
    WindowWatch::SnapshotIngest.call(payload: ww_payload(month: "2026-09", trade_date: "2026-10-09"), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path(month: "2026-09")
    assert_includes response.body, "判定月：2026-09 月K收盘"
    get window_watch_path(month: "2999-01")
    assert_includes response.body, "判定月：2026-10 月K收盘"
  end

  test "R2 全量视图检索：名称/代码过滤，通配符剥离不报错" do
    sign_in users(:two)
    get window_watch_path(view: "all", q: "核电")
    assert_includes response.body, "中国核电"
    refute_includes response.body, "五粮液"

    get window_watch_path(view: "all", q: "600519")
    assert_includes response.body, "贵州茅台"
    refute_includes response.body, "中国核电"

    get window_watch_path(view: "all", q: "%_%") # 剥离后空串=不过滤
    assert_response :success
  end

  # ---- R3 ④持仓管理区块（契约 v0.5 / snapshot 1.2）----

  test "v1.2：④区块渲染逐股明细，金字塔序、三时点叙事、固定副标题逐字" do
    WindowWatch::SnapshotIngest.call(payload: ww_payload(in_position: true), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    seg = response.body[/<section id="ww-inpos".*?<\/section>/m].to_s
    assert_includes seg, WindowWatchHelper::IN_POSITION_SUBTITLE
    assert_includes seg, "中国平安"
    assert_includes seg, "泸州老窖"
    assert_operator seg.index("中国平安"), :<, seg.index("泸州老窖"), "④块金字塔序（65>45）"
    assert_includes seg, "开窗 2025-03 · 入场 2025-06 · 持仓 16 个月"
    # 入场月晚于判定月=正常形态，如实展示（口径②）
    assert_includes seg, "开窗 2026-02 · 入场 2026-11 · 持仓 1 个月"
    # 计数条升五档：④出现
    assert_includes response.body, "④持仓管理"
  end

  test "v1.1 兼容降级：无逐股行时④区块仅计数提示" do
    payload = ww_payload
    payload["stats"]["in_position_count"] = 5
    WindowWatch::SnapshotIngest.call(payload: payload, source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "共 5 只；逐股明细将随下一批快照（snapshot 1.2）提供。"
    refute_includes response.body, "中国平安"
  end

  test "v1.1 默认包（in_position_count=0）：④区块与计数条④段均不出现" do
    sign_in users(:two)
    get window_watch_path
    refute_includes response.body, "④持仓管理"
  end

  test "全量视图可按持仓管理档筛选" do
    WindowWatch::SnapshotIngest.call(payload: ww_payload(in_position: true), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path(view: "all", tier: "IN_POSITION")
    assert_includes response.body, "中国平安"
    refute_includes response.body, "中国核电"
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
