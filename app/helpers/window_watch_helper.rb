module WindowWatchHelper
  TIER_NAMES = {
    "T1" => "开窗观察", "T2_P2" => "形成中·红柱收敛",
    "T2_P1" => "形成中·绿柱收敛", "T3" => "状态A·暂不开窗"
  }.freeze
  TIER_SHORT_NAMES = {
    "T1" => "开窗观察", "T2_P2" => "红柱收敛", "T2_P1" => "绿柱收敛", "T3" => "暂不开窗"
  }.freeze
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

  def ww_quality_badge
    ww_badge "质量达标",
             "最近一份已披露年报口径下，ROE≥15% 且经营现金流为正、连续3年。as-of 截至 #{@snapshot.month} 次月1日已披露年报",
             "border-ink-soft text-ink bg-white"
  end

  # 判定月应为「最后一个已收完月」= 上一自然月（K4），用于 R4 最新月缺失提示
  def ww_expected_month
    (Date.current << 1).strftime("%Y-%m")
  end
end
