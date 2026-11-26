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
    # 美的 [11,16,18]：连续15 不命中（11<15）；平均15 命中（均值15.0≥15 且 min 11≥10.5）——三维口径差异样本
    ww_give_financials("SZ000333", roes: [11, 16, 18])
  end

  # ---- §一 访问控制（2026-11-25 正式发布：会员完整视图 + 非会员/游客 teaser，不再重定向）----

  test "正式发布：未登录访问返回非会员 teaser，不暴露个股" do
    get window_watch_path
    assert_response :success
    assert_includes response.body, "个股名单为会员内容"
  end

  test "正式发布：会员见完整视图，普通用户仍为 teaser" do
    member = User.create!(email: "ww-member@test.local", password: "WwMember2026!", nickname: "开窗会员账号",
                          role: "member", member_expire_at: 1.year.from_now,
                          confirmed_at: Time.current, onboarded_at: Time.current)
    sign_in member
    get window_watch_path
    assert_includes response.body, "中国核电"

    sign_in users(:one)
    get window_watch_path
    assert_includes response.body, "个股名单为会员内容"
    refute_includes response.body, "中国核电"
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
    assert_equal 4, WindowWatch::FinancialPreset.preset_metrics(years: 3, mode: "consecutive", band: 15).size
  end

  # ---- 三维筛选（2026-11-25 老板定：年数 × 满足方式 × 阈值）----

  test "平均满足 15%：连续不命中的美的进入视图，ROE(筛选值)列=算术平均主值" do
    sign_in users(:two)
    get window_watch_path(view: "main", years: 3, mode: "average", band: 15)
    seg = response.body[/<section id="ww-t2p2".*?<\/section>/m].to_s
    assert_includes seg, "美的集团"
    assert_includes seg, "15.0%" # (11+16+18)/3=15.0，平均满足主值
  end

  test "连续满足：ROE(筛选值)列=N年最小值主值（核电 16.0）" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    assert_includes response.body, "16.0%"
  end

  test "5 年窗口要求 5 期年报：仅 3 期数据的股票不命中" do
    sign_in users(:two)
    get window_watch_path(view: "main", years: 5, band: 10)
    refute_includes response.body, "中国核电"
    assert_includes response.body, "本月开窗观察暂无股票"
  end

  test "非法 years/mode 参数回落默认（3年/连续满足）" do
    sign_in users(:two)
    get window_watch_path(view: "main", years: 4, mode: "xyz", band: 15)
    refute_includes response.body, "美的集团" # 回落=连续满足15，美的不命中
  end

  test "计数条=命中子集：预设视图红柱收敛 0，全量视图仍为 stats 全量" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    assert_includes response.body, "（红柱收敛 0 / 绿柱收敛 1）"
    get window_watch_path(view: "all")
    assert_includes response.body, "（红柱收敛 2 / 绿柱收敛 1）"
  end

  test "卡片显示板块 · 行业 与金字塔分数列" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    assert_includes response.body, "公用事业 · 电力"
    t1_seg = response.body[/<section id="ww-t1".*?<\/section>/m].to_s
    assert_includes t1_seg, "网站金字塔综合分"
    assert_includes t1_seg, "85" # 招行金字塔分，T1 首行
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

  test "ROE(筛选值)列取预设主值而非最新单年；全量视图 ROE 列=最新披露年报" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    refute_includes response.body, "ROE 18.0%" # 预设视图不再渲染最新单年 ROE 徽章（核电主值=16.0）
    refute_includes response.body, "质量达标"
    get window_watch_path(view: "all")
    assert_includes response.body, "最新披露年报加权 ROE（财务库口径）"
  end

  # ---- 2026-11-25 老板定六点改版 ----

  test "列头说明位于每个区块名头与列表之间" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    t1_seg = response.body[/<section id="ww-t1".*?<\/section>/m].to_s
    assert_operator t1_seg.index("① 开窗观察"), :<, t1_seg.index("名称/代码 · 板块行业"), "列头在名头之后"
    assert_operator t1_seg.index("名称/代码 · 板块行业"), :<, t1_seg.index("招商银行"), "列头在列表之前"
  end

  test "已收藏股票显示实心星标、未收藏无星标；整行跳转与新窗口链接在位" do
    sign_in users(:two)
    UserFavorite.create!(user: users(:two), stock: Stock.find_by!(symbol: "SH600036"), rating: 4)
    get window_watch_path(view: "main", band: 15)
    t1_seg = response.body[/<section id="ww-t1".*?<\/section>/m].to_s
    assert_includes t1_seg, 'title="已收藏"' # 招行=已收藏打星
    assert_equal 1, t1_seg.scan(/title="已收藏"/).size # 核电=未收藏，无任何星标控件
    refute_includes response.body, 'data-controller="favorite-rating"' # 本页不做行内收藏交互（老板更正）
    assert_includes response.body, 'data-controller="ww-row-link"'
    assert_includes response.body, 'data-stock-url="/stocks/SH600036"'
    assert_includes response.body, 'target="_blank"'
  end

  test "金字塔数值用市场主题色（A股绿）" do
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    t1_seg = response.body[/<section id="ww-t1".*?<\/section>/m].to_s
    assert_includes t1_seg, "text-green-600"
  end

  test "常态横幅不再显示数据截至日；判定月与更新节奏保留" do
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "判定月：2026-10 月K收盘｜每月更新一次，月中不刷新"
    refute_includes response.body, "数据截至 2026-11-04"
  end

  test "全量视图统一卡片样式：列头/档位徽章齐备，收藏仅展示星标" do
    sign_in users(:two)
    get window_watch_path(view: "all")
    assert_includes response.body, "名称/代码 · 板块行业"
    refute_includes response.body, 'data-controller="favorite-rating"' # 星标为纯展示，无行内表单
    assert_includes response.body, "所属档位" # 档位徽章 tooltip
  end

  # ---- 2026-11-25 老板定全量视图四项优化 ----

  test "全量视图默认按金字塔分降序（茅台90 > 招行85 > 核电70）" do
    sign_in users(:two)
    get window_watch_path(view: "all")
    body = response.body
    assert_operator body.index("贵州茅台"), :<, body.index("招商银行"), "金字塔序"
    assert_operator body.index("招商银行"), :<, body.index("中国核电"), "金字塔序"
    assert_includes body, "金字塔分高→低"
  end

  test "全量视图板块筛选：金融板块只含招行/平安" do
    sign_in users(:two)
    WindowWatch::SnapshotIngest.call(payload: ww_payload(in_position: true), source_ip: "127.0.0.1")
    get window_watch_path(view: "all", sector: "金融")
    assert_includes response.body, "招商银行"
    assert_includes response.body, "中国平安"
    refute_includes response.body, "贵州茅台"
    # 板块选项列表在位 + 档筛选链接保留板块条件
    assert_includes response.body, "公用事业"
    assert_includes response.body, "sector=%E9%87%91%E8%9E%8D"
  end

  test "非法板块回落全部" do
    sign_in users(:two)
    get window_watch_path(view: "all", sector: "不存在的板块")
    assert_response :success
    assert_includes response.body, "贵州茅台"
  end

  test "检索框挂A股补全组件；选择元素挂缓存组件" do
    sign_in users(:two)
    get window_watch_path(view: "all")
    assert_includes response.body, 'data-controller="ww-search"'          # 导航栏同款模糊补全（market=CN）
    assert_includes response.body, 'data-controller="ww-selection-cache"' # localStorage 选择记忆
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

    # 评审修复5：改名股按当前库名可命中（检索同时匹配 stocks.name，展示名优先当前库）
    Stock.find_by!(symbol: "SZ000333").update_column(:name, "美的集团G")
    get window_watch_path(view: "all", q: "集团G")
    assert_includes response.body, "美的集团G"
    refute_includes response.body, "中国核电"
  end

  # ---- R3 ④持仓管理区块（契约 v0.5 / snapshot 1.2）----

  test "v1.2：④区块渲染逐股明细（跟随预设），金字塔序、三时点叙事、固定副标题逐字" do
    WindowWatch::SnapshotIngest.call(payload: ww_payload(in_position: true), source_ip: "127.0.0.1")
    ww_give_financials("SH601318", roes: [16, 17, 18])
    ww_give_financials("SZ000568", roes: [15, 16, 17])
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
    # 计数条升五档：④=命中子集计数
    assert_includes response.body, "④持仓管理"
  end

  test "④跟随预设筛选：无财务命中的持仓股不进④块" do
    WindowWatch::SnapshotIngest.call(payload: ww_payload(in_position: true), source_ip: "127.0.0.1")
    ww_give_financials("SH601318", roes: [16, 17, 18]) # 平安命中 15%；老窖无财务数据不命中
    sign_in users(:two)
    get window_watch_path(view: "main", band: 15)
    seg = response.body[/<section id="ww-inpos".*?<\/section>/m].to_s
    assert_includes seg, "中国平安"
    refute_includes seg, "泸州老窖"
  end

  test "v1.1 兼容降级：无逐股行时④区块仅全量计数提示" do
    payload = ww_payload
    payload["stats"]["in_position_count"] = 5
    WindowWatch::SnapshotIngest.call(payload: payload, source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path
    assert_includes response.body, "共 5 只（全量口径，未含预设过滤）；逐股明细将随下一批快照（snapshot 1.2）提供。"
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

  test "冷启动：含市场切换入口（另一市场可能已有快照）" do
    WindowWatchSnapshot.destroy_all
    get window_watch_path
    assert_includes response.body, "window-watch?market=US"
    get window_watch_path(market: "US")
    assert_includes response.body, "window-watch?market=CN"
    assert_includes response.body, "美股（普通股与 ADR）"
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

  # ---- 非会员 teaser 内容（2026-11-25 老板定：计数=默认财务预设口径、无免责声明）----

  test "teaser：计数条与会员默认主组视图同口径（除③），且不展示免责声明" do
    get window_watch_path
    assert_includes response.body, "用于时机选择和定位"
    refute_includes response.body, WindowWatchSnapshotHelper::WW_DISCLAIMER
    teaser_counts = ww_count_bar_numbers(response.body)
    refute_empty teaser_counts
    refute teaser_counts.key?("③状态A·暂不开窗"), "teaser 计数条不应含③暂不开窗"

    sign_in users(:two)
    get window_watch_path(view: "main")
    member_counts = ww_count_bar_numbers(response.body)
    assert member_counts.key?("③状态A·暂不开窗"), "会员视图计数条应保留③暂不开窗"
    assert_equal member_counts.except("③状态A·暂不开窗"), teaser_counts
  end

  # 提取计数条卡片内各档数字（①②③④主计数 + 红/绿柱收敛子计数）为哈希，用于会员/非会员同口径断言
  def ww_count_bar_numbers(body)
    bar = body[/<div class="hl-card px-4 py-3 flex flex-wrap.*?<\/div>/m, 0].to_s
    counts = {}
    ["①开窗观察", "②形成中", "③状态A·暂不开窗", "④持仓管理"].each do |label|
      value = bar[/#{Regexp.escape(label)}\s*<span[^>]*>(\d+)<\/span>/, 1]
      counts[label] = value if value
    end
    red, green = bar.scan(/红柱收敛\s*(\d+)\s*\/\s*绿柱收敛\s*(\d+)/).flatten
    counts["红柱收敛"], counts["绿柱收敛"] = red, green if red && green
    counts
  end

  # ---- 契约 v0.8 US tab（与 A 股同一样式组件，market 参数贯穿）----

  test "US tab 会员视图：渲染美股快照行，不串 CN；判定月横幅与 US 免责逐字" do
    ww_create_us_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload(market: "US", in_position: true), source_ip: "127.0.0.1")
    ww_give_us_financials("NVDA", roes: [20, 25, 30])
    ww_give_us_financials("AAPL", roes: [30, 31, 32])
    sign_in users(:two)
    get window_watch_path(market: "US", view: "all")
    assert_includes response.body, "英伟达"
    assert_includes response.body, "BRK.A.US"
    refute_includes response.body, "中国核电" # CN 行不串台
    assert_includes response.body, "判定月：2026-10 月K收盘"
    assert_includes response.body, WindowWatchSnapshotHelper::WW_US_DISCLAIMER
  end

  test "US 预设视图：非 12-31 财年截止（10-31）照常命中；未达档不进" do
    ww_create_us_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload(market: "US"), source_ip: "127.0.0.1")
    ww_give_us_financials("NVDA", roes: [20, 25, 30])
    ww_give_us_financials("BRK.A", roes: [12, 13, 14])
    sign_in users(:two)
    get window_watch_path(market: "US", view: "main", band: 15)
    assert_includes response.body, "英伟达"
    refute_includes response.body, "伯克希尔哈撒韦A" # ROE 12-14 不达 15 档
    metrics = WindowWatch::FinancialPreset.preset_metrics(years: 3, mode: "consecutive", band: 15, market: "US")
    assert_equal 20.0, metrics["NVDA"] # 连续满足主值=3 份年报最小值
  end

  test "同月 CN/US 双包：默认 market=CN 渲染 CN 包，US 参数渲染 US 包，互不影响" do
    ww_create_us_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload(market: "US"), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path(view: "all")
    assert_includes response.body, "中国核电"
    refute_includes response.body, "英伟达"
    get window_watch_path(market: "US", view: "all")
    assert_includes response.body, "英伟达"
    refute_includes response.body, "中国核电"
    # 评审修复4+市场记忆：tab 保留判定月、刻意不带 view（进入后由 ww-selection-cache restore 套用该市场记忆）
    assert_includes response.body, "window-watch?market=CN&amp;month=2026-10"
    refute_includes response.body, "window-watch?market=CN&amp;month=2026-10&amp;view="
  end

  test "非法 market 参数回落 CN" do
    sign_in users(:two)
    get window_watch_path(market: "HK")
    assert_includes response.body, "中国核电"
  end

  test "US 无快照冷启动：文案标注美股范围，CN 快照不串台" do
    sign_in users(:two)
    get window_watch_path(market: "US")
    assert_includes response.body, "美股（普通股与 ADR）"
    assert_includes response.body, "数据正在准备，首个快照尚未生成"
    refute_includes response.body, "中国核电"
  end

  test "US 全量视图：GICS 行业筛选 + 代码检索 + 详情页链接（裸码路由）" do
    ww_create_us_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload(market: "US"), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path(market: "US", view: "all", industry: "Financials")
    assert_includes response.body, "伯克希尔哈撒韦A"
    refute_includes response.body, "英伟达"
    # to_param 交易所前缀 + 带点码 URL 转下划线（NYSE-BRK_A）
    assert_includes response.body, 'data-stock-url="/stocks/NYSE-BRK_A"'
    get window_watch_path(market: "US", view: "all", q: "BRK")
    assert_includes response.body, "伯克希尔哈撒韦A"
  end

  test "US teaser（非会员）：计数=US 默认预设口径，不含个股与免责" do
    ww_create_us_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload(market: "US"), source_ip: "127.0.0.1")
    ww_give_us_financials("NVDA", roes: [20, 25, 30])
    get window_watch_path(market: "US")
    assert_includes response.body, "美股（普通股与美国存托凭证 ADR）"
    assert_includes response.body, "个股名单为会员内容"
    refute_includes response.body, "英伟达"
    refute_includes response.body, WindowWatchSnapshotHelper::WW_US_DISCLAIMER
    # 契约 v0.8：非会员页也有市场切换入口（美股 teaser 可达性）
    assert_includes response.body, "window-watch?market=CN"
    assert_includes response.body, "bg-ink text-white font-medium" # 美股为当前激活
  end

  test "CN teaser 同样含市场切换入口，可直达美股 teaser" do
    get window_watch_path
    assert_includes response.body, "window-watch?market=US"
  end

  test "金融标签市场口径：US 按 sector=金融服务 整板块（BRK.A 命中、NVDA 不命中），tooltip 分市场" do
    ww_create_us_stocks!
    WindowWatch::SnapshotIngest.call(payload: ww_payload(market: "US"), source_ip: "127.0.0.1")
    sign_in users(:two)
    get window_watch_path(market: "US", view: "all")
    # BRK.A fixture sector=金融服务（信用服务类，同 MA/V）→ 唯一命中；科技/消费/工业板块不标
    assert_equal 1, response.body.scan("金融行业（GICS 金融服务板块）").size
    refute_includes response.body, "金融行业（银行/证券/保险）"
    # CN 口径零变化：招行 industry=银行 仍走现成正则
    get window_watch_path(view: "all")
    assert_includes response.body, "金融行业（银行/证券/保险）"
  end
end
