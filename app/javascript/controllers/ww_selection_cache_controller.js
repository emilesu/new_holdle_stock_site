import { Controller } from "@hotwired/stimulus"

// 开窗观察选择记忆（2026-11-25 老板定，语义严格对齐金字塔页惯例；2026-11-26 v0.8 扩展至美股）：
// ① 只在用户交互时保存（筛选链接点击 / 表单提交）——分享链接带参数进入不覆盖本机偏好；
// ② 按「市场 × 视图」双层分组：A股/美股各自独立记忆 view 与组内选项，互不串组；
//    组内 URL 缺失的键记为空=显式重置（档「全部」等），另一视图组保留；
//    市场切换 tab（链接无 view）只更新市场偏好、不覆写目标市场选项组（防来回切换清空）；
//    进入目标市场后因 URL 无 view，restore 自动套用该市场记忆的视图+选项；
// ③ 裸 URL（无 view 参数）进入时套用缓存（Turbo.visit replace）：URL 显式带 market 时以其为准、
//    仅套用该市场的选项缓存；裸 URL 连市场一起恢复（上次看美股→回来仍是美股）；
//    非受控参数（month/q/page）原样保留；缓存与当前默认一致（CN+main 且组内全空）时不产生多余导航；7 天有效。
// 取值合法性由服务端白名单回落兜底（market 枚举 / presence_in / band_for 等），缓存被篡改也不会越权。
const KEY = "windowwatch_last_v2"
const LEGACY_KEY = "windowwatch_last_v1" // v2 结构不兼容，首次连接即清理残留（评审修复）
const TTL = 7 * 24 * 60 * 60 * 1000
const MAIN_KEYS = ["years", "mode", "band"]
const ALL_KEYS = ["tier", "sector", "industry", "sort"]
const MARKETS = ["CN", "US"]
// restore 重建 URL 时由缓存接管的键——其余参数（month/q/page 等）原样保留（评审修复：外链 ?month=X 不再被丢）
const CONTROL_KEYS = ["view", "market", ...MAIN_KEYS, ...ALL_KEYS]

export default class extends Controller {
  connect() {
    try { localStorage.removeItem(LEGACY_KEY) } catch (e) { /* 存储不可用时静默忽略 */ }
    this.clickHandler = (event) => this.onLinkClick(event)
    this.submitHandler = (event) => this.onFormSubmit(event)
    document.addEventListener("click", this.clickHandler)
    document.addEventListener("submit", this.submitHandler)
    this.restore()
  }

  disconnect() {
    document.removeEventListener("click", this.clickHandler)
    document.removeEventListener("submit", this.submitHandler)
  }

  // 交互保存：本页筛选链接（含 view 参数、同路径）、市场切换 tab（仅 market）与筛选/切换表单
  onLinkClick(event) {
    const anchor = event.target.closest("a")
    if (!anchor) return
    let url
    try { url = new URL(anchor.href, location.origin) } catch (e) { return }
    if (url.pathname !== location.pathname) return
    const params = url.searchParams
    if (!params.has("view") && !params.has("market")) return
    this.saveFrom(params)
  }

  onFormSubmit(event) {
    const form = event.target
    if (!form.querySelector || !form.querySelector("input[name='view']")) return
    const params = new URLSearchParams(new FormData(form))
    if (!params.has("view")) return
    this.saveFrom(params)
  }

  // market 缺省=CN（老分享链接无 market 参数）；非法值同回落 CN，与服务端白名单口径一致
  marketOf(params) {
    return MARKETS.includes(params.get("market")) ? params.get("market") : "CN"
  }

  saveFrom(params) {
    const market = this.marketOf(params)
    const pageMarket = this.marketOf(new URLSearchParams(location.search))
    const saved = this.readSaved()
    const views = { CN: {}, US: {}, ...((saved && saved.views) || {}) }

    // 市场切换 tab（无 view 或目标市场≠当前页市场）：只记「上次看哪个市场」，目标市场的视图与选项组原样保留；
    // 进入目标市场后由 restore 套用其记忆（tab 链接刻意不带 view，见 index.html.erb 注释）
    if (!params.has("view") || market !== pageMarket) {
      if (market === pageMarket) return // 点当前市场自己的 tab：缓存原样，不覆写
      try { localStorage.setItem(KEY, JSON.stringify({ ...saved, market, views, ts: Date.now() })) } catch (e) { /* 静默 */ }
      return
    }

    const view = params.get("view") === "all" ? "all" : "main"
    const keys = view === "all" ? ALL_KEYS : MAIN_KEYS
    const group = {}
    keys.forEach((key) => { group[key] = params.get(key) || "" })
    views[market] = { ...views[market], view, ...group }
    try { localStorage.setItem(KEY, JSON.stringify({ market, views, ts: Date.now() })) } catch (e) { /* 无痕模式等存储不可用时静默忽略 */ }
  }

  // 裸 URL（无 view 参数）进入才恢复；详见文件头③
  restore() {
    const url = new URLSearchParams(location.search)
    if (url.has("view")) return
    const saved = this.readSaved()
    if (!saved || Date.now() - (saved.ts || 0) > TTL) return

    const views = saved.views || {}
    const hasUrlMarket = MARKETS.includes(url.get("market"))
    const market = hasUrlMarket ? url.get("market") : (saved.market === "US" ? "US" : "CN")
    const sel = views[market] || {}
    const view = sel.view === "all" ? "all" : "main"
    const keys = view === "all" ? ALL_KEYS : MAIN_KEYS
    const active = keys.filter((key) => typeof sel[key] === "string" && sel[key].length > 0)
    // 无市场可恢复（裸 URL+CN 或 URL 已带该市场）且选项即默认 → 不产生多余导航
    if (view === "main" && active.length === 0 && (market === "CN" || hasUrlMarket)) return

    const params = new URLSearchParams()
    // 保留原 URL 非受控参数（month/q/page…）；非法 market（如 HK）属受控键已被剔除，由缓存市场接管
    url.forEach((value, key) => { if (!CONTROL_KEYS.includes(key)) params.set(key, value) })
    if (market === "US") params.set("market", "US")
    params.set("view", view)
    active.forEach((key) => params.set(key, sel[key]))
    window.Turbo.visit(`${location.pathname}?${params.toString()}`, { action: "replace" })
  }

  readSaved() {
    try { return JSON.parse(localStorage.getItem(KEY)) } catch (e) { return null }
  }
}
