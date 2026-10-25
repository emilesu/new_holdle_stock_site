import { Controller } from "@hotwired/stimulus"

// 股票收藏页交互：
// 1. 输入即搜：关键词输入 300ms 防抖后自动提交。表单放在 turbo-frame 之外，只刷新结果区，
//    因此输入框的值、光标位置与中文输入法组词状态都不会被替换
// 2. 市场/板块/评分/排序下拉与「按市场分组」开关变更后立即提交，无需防抖
// 3. 中文输入法组词（isComposing）期间不提交，组词结束补一次，避免打断拼音候选项
// 4. 加载时给结果区占位反馈；加载完成后用服务端实际请求的 URL 同步地址栏
//    （分页链接在 frame 内部、不经过本控制器的提交逻辑，需由 frame 渲染事件兜底）
// 5. 「清除筛选」按钮复位全部条件后立即提交，避免 URL 与控件值不一致
export default class extends Controller {
  static targets = ["form", "query", "groupInput", "groupButton", "results", "loadingHint"]
  static DEBOUNCE_MS = 300
  // 记住上次筛选条件（与金字塔页 / 股票筛选页同一思路：localStorage + 7 天有效）
  static STORAGE_KEY = "favorites_last_v1"
  static STORAGE_TTL = 7 * 24 * 60 * 60 * 1000
  // 参与记忆的筛选字段：URL 已带任一参数（含页码）时以 URL 为准，不套用缓存
  static FILTER_KEYS = ["q", "market", "sector", "score_range", "sort", "group", "page"]

  connect() {
    this.timer = null
    // 取消收藏由 turbo_stream 移除行：被移除的行必然属于当前筛选结果，
    // 因此「筛选出 N 只」就地减 1（总数由服务端在同一个流里替换）
    this.streamHandler = (event) => {
      const stream = event.detail?.newStream
      if (!stream || stream.getAttribute("action") !== "remove") return
      if (!String(stream.getAttribute("target") || "").startsWith("favorite_card_")) return
      this.decrementFilteredSummary()
    }
    document.addEventListener("turbo:before-stream-render", this.streamHandler)
    this.restoreFromStorage()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.streamHandler)
    this.clearTimer()
  }

  decrementFilteredSummary() {
    const el = this.element.querySelector("#favorites_filtered_summary")
    if (!el) return
    const current = Number.parseInt(el.textContent, 10)
    if (Number.isNaN(current)) return
    el.textContent = String(Math.max(0, current - 1))
  }

  // ---------- 输入即搜 ----------

  search(event) {
    // 组词中（拼音候选未上屏）不提交
    if (event && event.isComposing) return
    this.clearTimer()
    this.timer = setTimeout(() => this.submit(), this.constructor.DEBOUNCE_MS)
  }

  // 组词结束后补一次提交：组词期间被 isComposing 拦下的那次不能丢
  compositionEnd() {
    this.submitNow()
  }

  // ---------- 下拉 / 分组开关：立即提交 ----------

  submitNow() {
    this.clearTimer()
    this.submit()
  }

  submit() {
    this.clearTimer()
    this.persist()
    this.formTarget.requestSubmit()
  }

  // ---------- 记住上次筛选条件 ----------

  persist() {
    const form = this.formTarget
    const fields = {}
    new FormData(form).forEach((value, key) => { fields[key] = String(value) })
    // 全默认态（如清除筛选后的提交）不落缓存，避免下次无参进入时触发与首屏相同的冗余恢复提交
    const hasFilter = ["q", "market", "sector", "score_range"].some((key) => form.elements[key]?.value) ||
      ["score", "rating"].includes(form.elements["sort"]?.value) ||
      form.elements["group"]?.value === "market"
    try {
      if (hasFilter) {
        localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify({ fields, ts: Date.now() }))
      } else {
        localStorage.removeItem(this.constructor.STORAGE_KEY)
      }
    } catch (e) { /* 无痕模式等存储不可用时静默忽略 */ }
  }

  clearStored() {
    try { localStorage.removeItem(this.constructor.STORAGE_KEY) } catch (e) { /* 忽略 */ }
  }

  // 无参数进入时套用缓存；URL 已带条件（含分享 / 刷新回显）时以 URL 为准
  restoreFromStorage() {
    const params = new URLSearchParams(window.location.search)
    if (this.constructor.FILTER_KEYS.some((key) => params.has(key))) return

    let saved = null
    try { saved = JSON.parse(localStorage.getItem(this.constructor.STORAGE_KEY)) } catch (e) { return }
    if (!saved || !saved.fields || Date.now() - (saved.ts || 0) > this.constructor.STORAGE_TTL) return

    const form = this.formTarget
    Object.entries(saved.fields).forEach(([key, value]) => {
      const el = form.elements[key]
      if (!el) return
      // 非会员的评分控件被禁用（disabled 控件不提交，服务端也会丢弃该参数）
      if (el.disabled) return
      if (el.tagName === "SELECT") {
        const option = [...el.options].find((candidate) => candidate.value === value)
        // 缓存值可能已失效：板块随取消收藏从下拉消失，或会员降级后评分选项被禁用——恢复不了就跳过
        if (!option || option.disabled) return
      }
      el.value = value
    })
    this.groupButtonTarget.setAttribute("aria-pressed", String(this.groupInputTarget.value === "market"))
    // 恢复后走一次正常提交：服务端渲染结果区 + frameRendered 同步地址栏
    if (this.constructor.FILTER_KEYS.some((key) => form.elements[key]?.value)) {
      this.submitNow()
    }
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  // ---------- 按市场分组 ----------

  toggleGroup() {
    const grouped = this.groupInputTarget.value === "market"
    this.groupInputTarget.value = grouped ? "" : "market"
    this.groupButtonTarget.setAttribute("aria-pressed", String(!grouped))
    this.submitNow()
  }

  // ---------- 清除筛选 ----------

  resetForm() {
    const form = this.formTarget
    ;["q", "market", "sector", "score_range"].forEach((name) => {
      if (form.elements[name]) form.elements[name].value = ""
    })
    // 排序需回到合法默认值，否则下拉没有匹配项会呈现空选中态
    if (form.elements["sort"]) form.elements["sort"].value = "recent"
    this.groupInputTarget.value = ""
    this.groupButtonTarget.setAttribute("aria-pressed", "false")
    this.clearStored()
    this.submitNow()
  }

  // ---------- 加载反馈与地址栏同步 ----------

  loading(event) {
    // 只对「工具栏表单提交」与「frame 自身导航（点分页）」置位。
    // 行内取消收藏（turbo_stream）与行内链接的 Turbo 预取都不会触发 turbo:frame-load，
    // 若一并置位，结果区会永久停留在置灰 + pointer-events-none，列表点不动
    if (event.target !== this.formTarget && event.target !== this.resultsTarget) return
    this.setLoading(true)
  }

  frameLoaded() {
    this.setLoading(false)
  }

  // 用服务端实际请求的 URL 同步地址栏（含分页参数），保证刷新/分享可还原当前视图
  frameRendered(event) {
    const url = event.detail?.fetchResponse?.response?.url
    if (!url) return
    history.replaceState(history.state, "", url)
  }

  setLoading(on) {
    this.resultsTarget.setAttribute("aria-busy", on ? "true" : "false")
    this.resultsTarget.classList.toggle("opacity-60", on)
    this.resultsTarget.classList.toggle("pointer-events-none", on)
    this.loadingHintTargets.forEach((el) => el.classList.toggle("hidden", !on))
  }
}
