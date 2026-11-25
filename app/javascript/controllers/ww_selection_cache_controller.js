import { Controller } from "@hotwired/stimulus"

// 开窗观察选择记忆（2026-11-25 老板定，对齐金字塔页 localStorage 惯例，7 天有效）：
// URL 带筛选参数 → 写入缓存；裸 URL 进入 → 套用缓存（Turbo.visit replace）
// 只记选择元素（视图/年数/满足方式/阈值/档/板块/行业/排序）；检索词 q、判定月 month、分页 page 不记忆
// 取值合法性由服务端白名单回落兜底（presence_in / band_for 等），缓存被篡改也不会越权
const KEY = "windowwatch_last_v1"
const TTL = 7 * 24 * 60 * 60 * 1000
const KEYS = ["view", "years", "mode", "band", "tier", "sector", "industry", "sort"]

export default class extends Controller {
  connect() {
    const params = new URLSearchParams(location.search)
    const selection = {}
    KEYS.forEach((key) => { if (params.has(key)) selection[key] = params.get(key) })

    if (Object.keys(selection).length > 0) {
      try {
        localStorage.setItem(KEY, JSON.stringify({ ...selection, ts: Date.now() }))
      } catch (e) { /* 无痕模式等存储不可用时静默忽略 */ }
      return
    }

    let saved = null
    try { saved = JSON.parse(localStorage.getItem(KEY)) } catch (e) { return }
    if (!saved || Date.now() - (saved.ts || 0) > TTL) return

    const query = KEYS
      .filter((key) => typeof saved[key] === "string" && saved[key].length > 0)
      .map((key) => `${key}=${encodeURIComponent(saved[key])}`)
      .join("&")
    if (query) window.Turbo.visit(`${location.pathname}?${query}`, { action: "replace" })
  }
}
