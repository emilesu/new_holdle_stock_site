require "test_helper"
require_relative "../support/window_watch_snapshot_helper"

# R8/V6/V7/V11/V12 自动化红线扫描（需求单 §六/§七，纪要决议6）：
# 四种渲染态全页 HTML（含 alt/meta/tooltip）扫描——红线词 0 命中、绝对数值 0 渲染、固定文案逐字在位
class WindowWatchRedlineTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include WindowWatchSnapshotHelper

  # §六.1 词表（v0.3.0 增「质量达标」；v0.2.1 增「状态A形成中」）+ §六.3 禁用术语（含 alt/meta/tooltip 全文扫描）
  FORBIDDEN_WORDS = %w[即将 预测 建议买入 建议卖出 可以关注 值得买入 目标价 止损价 高转矮 状态A形成中 质量达标].freeze

  setup do
    ww_create_stocks!
    # v1.2 全结构（含④持仓管理逐股行）：红线扫描覆盖 ④ 区块
    WindowWatch::SnapshotIngest.call(payload: ww_payload(in_position: true), source_ip: "127.0.0.1")
    ww_give_financials("SH601985", roes: [16, 17, 18])
    ww_give_financials("SH600036", roes: [18, 19, 20])
    ww_give_financials("SH600519", roes: [30, 31, 32])
    ww_give_financials("SZ300750", roes: [24, 25, 26])
    # 平安进预设 → ④区块（含固定副标题）参与红线扫描
    ww_give_financials("SH601318", roes: [16, 17, 18])
    sign_in users(:two)
  end

  def rendered_states
    {
      "会员主组视图" => window_watch_path,
      "会员全量视图" => window_watch_path(view: "all"),
      "全量空档态" => window_watch_path(view: "all", tier: "T2_P1", industry: "电池")
    }
  end

  test "V6：三种渲染态红线词 0 命中" do
    bodies = rendered_states.each_with_object({}) do |(name, path), acc|
      get path
      assert_response :success
      acc[name] = response.body
    end
    bodies.each_value do |body|
      FORBIDDEN_WORDS.each { |w| refute_includes body, w, "红线词命中：#{w}" }
    end
  end

  test "V11：MACD 系绝对数值（hist/prev_hist/dif/dea/ratio）不出现在页面正文（含两位小数形态）" do
    [window_watch_path, window_watch_path(view: "all")].each do |path|
      get path
      # 扫描范围限 <main> 页面正文（导航/页脚 SVG 图标路径含大量小数，属版式 chrome 非数据渲染）
      body = response.body[/<main\b.*?<\/main>/m].to_s
      # 同理剔除行内图标（收藏星等）的 path d 数据：其为固定字形坐标，与判定数值无关（数据几何仍全量在扫）
      body = body.gsub(/\sd="[^"]*"/, "")
      refute_empty body
      (WindowWatchSnapshotHelper::WW_STOCKS + WindowWatchSnapshotHelper::WW_IN_POSITION).each do |r|
        %w[hist prev_hist dif dea ratio].each do |field|
          raw = r[field.to_sym].to_s
          rounded = format("%.2f", r[field.to_sym].to_f)
          refute_includes body, raw, "#{field}=#{raw} 出现在 HTML"
          refute_includes body, rounded, "#{field} 两位小数形态 #{rounded} 出现在 HTML"
        end
      end
    end
  end

  test "V7：四档副标题固定文案与 §六.2 逐字一致（主组视图）" do
    get window_watch_path
    WindowWatchHelper::TIER_SUBTITLES.each_value do |text|
      assert_includes response.body, text
    end
    # 契约 v0.5 §三.2：④持仓管理副标题为 DSH 确认版固定文案，逐字验收
    assert_includes response.body, WindowWatchHelper::IN_POSITION_SUBTITLE
    # §六.2 特别红线：绿柱收敛不得写成「状态A形成中」
    refute_includes response.body, "状态A形成中"
  end

  test "V12：非管理员访问被重定向，响应不含任何个股名称/代码（暗发布期）" do
    sign_out users(:two)
    get window_watch_path
    assert_redirected_to root_path
    WindowWatchSnapshotHelper::WW_STOCKS.each do |r|
      refute_includes response.body, r[:name]
      refute_includes response.body, r[:symbol]
      refute_includes response.body, r[:code].upcase
    end
  end
end
