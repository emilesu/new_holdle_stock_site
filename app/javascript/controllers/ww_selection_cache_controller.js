import { Controller } from "@hotwired/stimulus"

// 开窗观察选择记忆（2026-11-25 老板定，语义严格对齐金字塔页惯例）：
// ① 只在用户交互时保存（筛选链接点击 / 表单提交）——分享链接带参数进入不覆盖本机偏好；
// ② 按视图分组全量覆写本组：view=all 写 tier/sector/industry/sort，view=main 写 years/mode/band；
//    组内 URL 缺失的键记为空=显式重置（档「全部」等），另一组保留不被串组污染；
// ③ 仅裸 URL（无 view 参数）进入时套用缓存（Turbo.visit replace）；7 天有效。
// 取值合法性由服务端白名单回落兜底（presence_in / band_for 等），缓存被篡改也不会越权。
const KEY = "windowwatch_last_v1"
const TTL = 7 * 24 * 60 * 60 * 1000
const MAIN_KEYS = ["years", "mode", "band"]
const ALL_KEYS = ["tier", "sector", "industry", "sort"]

export default class extends Controller {
  connect() {
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

  // 交互保存：本页筛选链接（含 view 参数、同路径）与筛选/切换表单
  onLinkClick(event) {
    const anchor = event.target.closest("a")
    if (!anchor) return
    let url
    try { url = new URL(anchor.href, location.origin) } catch (e) { return }
    if (url.pathname !== location.pathname) return
    const params = url.searchParams
    if (!params.has("view")) return
    this.saveFrom(params)
  }

  onFormSubmit(event) {
    const form = event.target
    if (!form.querySelector || !form.querySelector("input[name='view']")) return
    const params = new URLSearchParams(new FormData(form))
    if (!params.has("view")) return
    this.saveFrom(params)
  }

  saveFrom(params) {
    const view = params.get("view") === "all" ? "all" : "main"
    const keys = view === "all" ? ALL_KEYS : MAIN_KEYS
    const prev = this.readSaved() || {}
    const next = { ...prev, view }
    keys.forEach((key) => { next[key] = params.get(key) || "" })
    next.ts = Date.now()
    try { localStorage.setItem(KEY, JSON.stringify(next)) } catch (e) { /* 无痕模式等存储不可用时静默忽略 */ }
  }

  // 裸 URL 进入才恢复；与当前默认一致（main 且组内全空）时不产生多余导航
  restore() {
    if (new URLSearchParams(location.search).has("view")) return
    const saved = this.readSaved()
    if (!saved || Date.now() - (saved.ts || 0) > TTL) return

    const view = saved.view === "all" ? "all" : "main"
    const keys = view === "all" ? ALL_KEYS : MAIN_KEYS
    const active = keys.filter((key) => typeof saved[key] === "string" && saved[key].length > 0)
    if (view === "main" && active.length === 0) return

    const params = new URLSearchParams({ view })
    active.forEach((key) => params.set(key, saved[key]))
    window.Turbo.visit(`${location.pathname}?${params.toString()}`, { action: "replace" })
  }

  readSaved() {
    try { return JSON.parse(localStorage.getItem(KEY)) } catch (e) { return null }
  }
}
