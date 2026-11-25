module WindowWatchHelper
  TIER_NAMES = {
    "T1" => "开窗观察", "T2_P2" => "形成中·红柱收敛",
    "T2_P1" => "形成中·绿柱收敛", "T3" => "状态A·暂不开窗",
    "IN_POSITION" => "持仓管理"
  }.freeze
  TIER_SHORT_NAMES = {
    "T1" => "开窗观察", "T2_P2" => "红柱收敛", "T2_P1" => "绿柱收敛", "T3" => "暂不开窗",
    "IN_POSITION" => "持仓管理"
  }.freeze
  # ④持仓管理区块副标题（契约 v0.5 §三.2，2026-11-25 DSH 确认版固定文案，V7 逐字验收）
  IN_POSITION_SUBTITLE = "以下股票已按 HOLDLE 方法论入场，截至数据更新日尚未出场。本区块为状态描述，不构成持仓建议。"
  # 需求单 v0.2.1 §六.2 固定文案（条件句，验收 V7 逐字比对，不得改写）
  TIER_SUBTITLES = {
    "T1" => "窗口已按方法论规则开启，存活期间可按方法论继续观察入场条件（切日K、绿柱回撤、突破前高）",
    "T2_P2" => "若次月收出可信且不高位的红柱，按方法论将构成开窗事件；若继续回落，本形态消失",
    "T2_P1" => "双线仍在 0 轴上方但状态A暂不成立；若次月收出可信且双线仍在 0 轴上方的红柱，按方法论状态A恢复、开窗事件同月成立；若次月红柱贴近 0 轴，按方法论归为绿柱，开窗顺延",
    "T3" => "状态A成立，但按规则当前不构成开窗事件"
  }.freeze
  # T3 档 subtag 行尾注（§3.2）
  T3_SUBTAG_NOTES = {
    "high_gate" => "柱已爬至两线上方，按规则高位不开窗",
    "no_low_premise" => "回落前提未形成"
  }.freeze

  # 徽章（必须带 tooltip，§六.6 不得裸标）
  def ww_badge(text, tip, extra_class = "border-line text-muted-2 bg-bg-mute")
    tag.span text, class: "hl-tip inline-flex items-center px-1.5 py-[1px] text-hl-11 rounded border whitespace-nowrap #{extra_class}",
             data: { tip: tip }, tabindex: "0"
  end

  # R1（2026-11-25 老板定）：①②区块展示前 10 只，其余折叠
  TOP_DISPLAY = 10

  # 预设列头行与卡片行共用六列栅格（身份|金字塔|ROE筛选值|形态|状态|标注），保证列对齐
  # 2026-11-25 老板定：金字塔列第二、ROE 筛选值列紧随其右；移动端两列=三行堆叠
  # 列宽系数刻意取整数：小数 fr（如 1.25fr）会撞 V11 绝对数值红线扫描的两位小数形态
  WW_CARD_GRID = "grid-cols-2 md:grid-cols-[minmax(0,25fr)_minmax(0,9fr)_minmax(0,12fr)_minmax(0,23fr)_minmax(0,21fr)_minmax(0,12fr)]"

  # ROE(筛选值) 列悬停说明：主值口径与三维筛选一致（连续=最小值，平均=算术平均）
  def ww_roe_metric_tip(mode, years)
    if mode == "average"
      "近#{years}财年 ROE 算术平均（平均满足判定主值，要求每年≥阈值×70%）"
    else
      "近#{years}财年 ROE 最小值（连续满足判定主值）"
    end
  end

  # 区块摘要头：N>10 时提示「显示前 10」
  def ww_block_summary(rows)
    rows.size > TOP_DISPLAY ? "#{rows.size} 只 · 显示前 #{TOP_DISPLAY}" : "#{rows.size} 只"
  end

  # 判定月应为「最后一个已收完月」= 上一自然月（K4），用于 R4 最新月缺失提示
  def ww_expected_month
    (Date.current << 1).strftime("%Y-%m")
  end
end
