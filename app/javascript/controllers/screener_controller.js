import { Controller } from "@hotwired/stimulus"

// 股票筛选页交互：
// 1. 市场/板块级联：切换市场或板块时从 /screener/filters 动态重建板块、行业下拉
// 2. 盈利指标/净利润条件启用开关联动输入框禁用状态（禁用的控件不会被 GET 提交，实现「留空即不启用」）
// 3. 浏览器返回（bfcache / Turbo 缓存恢复）后重新同步勾选与禁用状态，避免 UI 与实际状态不一致
// 4. 结果表整行点击新窗口打开股票详情
export default class extends Controller {
  static targets = ["form", "indicatorToggle", "indicatorInput", "growthToggle", "growthInput", "market", "sector", "industry", "scroller"]

  connect() {
    this.filterCache = {}
    this.syncAllState()
    // 浏览器表单状态恢复发生在 JS 执行之后，需在 pageshow / turbo:load 后延迟重同步一次
    this.restoreHandler = () => {
      this.syncAllState()
      requestAnimationFrame(() => this.syncAllState())
    }
    document.addEventListener("turbo:load", this.restoreHandler)
    window.addEventListener("pageshow", this.restoreHandler)
    this.restoreFromStorage()
  }

  // ---------- 记住上次筛选条件（localStorage，7 天有效） ----------

  static STORAGE_KEY = "screener_last_v1"
  static STORAGE_TTL = 7 * 24 * 60 * 60 * 1000

  persist() {
    const fields = {}
    new FormData(this.formTarget).forEach((v, k) => { fields[k] = String(v) })
    const toggles = { growth: this.growthToggleTarget.checked }
    this.indicatorToggleTargets.forEach((el) => { toggles[el.dataset.key] = el.checked })
    try {
      localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify({ fields, toggles, ts: Date.now() }))
    } catch (e) { /* 无痕模式等存储不可用时静默忽略 */ }
  }

  clearStored() {
    try { localStorage.removeItem(this.constructor.STORAGE_KEY) } catch (e) { /* 忽略 */ }
  }

  async restoreFromStorage() {
    // URL 已带筛选条件（服务端已回显）时不覆盖
    if (new URLSearchParams(window.location.search).has("screen")) return
    let saved = null
    try { saved = JSON.parse(localStorage.getItem(this.constructor.STORAGE_KEY)) } catch (e) { return }
    if (!saved || !saved.fields || Date.now() - (saved.ts || 0) > this.constructor.STORAGE_TTL) return

    const { market, sector, industry, ...rest } = saved.fields
    const m = market || this.marketTarget.value
    this.marketTarget.value = m
    // 级联三件套：服务端渲染的板块/行业选项对应默认市场，需按记忆值重建
    if (sector) {
      const { sectors } = await this.fetchFilters(m, null)
      this.renderOptions(this.sectorTarget, sectors, sector)
      const { industries } = await this.fetchFilters(m, sector)
      this.renderOptions(this.industryTarget, industries, industry || "")
      this.industryTarget.disabled = false
    } else {
      const { sectors } = await this.fetchFilters(m, null)
      this.renderOptions(this.sectorTarget, sectors, "")
      this.resetIndustry()
    }

    const form = this.formTarget
    Object.entries(rest).forEach(([k, v]) => {
      const el = form.elements[k]
      if (el) el.value = v
    })
    const toggles = saved.toggles || {}
    this.growthToggleTarget.checked = !!toggles.growth
    this.indicatorToggleTargets.forEach((el) => { el.checked = !!toggles[el.dataset.key] })
    this.syncAllState()
    form.requestSubmit()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.restoreHandler)
    window.removeEventListener("pageshow", this.restoreHandler)
  }

  syncAllState() {
    this.indicatorToggleTargets.forEach((el) => this.syncIndicator(el.dataset.key, el.checked))
    this.syncGrowth()
  }

  // ---------- 市场 / 板块 / 行业级联 ----------

  async marketChanged() {
    const market = this.marketTarget.value
    const { sectors } = await this.fetchFilters(market, null)
    // 响应乱序防护：市场已再次变化则丢弃过期响应
    if (this.marketTarget.value !== market) return
    this.renderOptions(this.sectorTarget, sectors, "")
    this.resetIndustry()
  }

  async sectorChanged() {
    const sector = this.sectorTarget.value
    if (!sector) {
      this.resetIndustry()
      return
    }
    const market = this.marketTarget.value
    this.industryTarget.disabled = true
    this.renderOptions(this.industryTarget, [], "", "加载中...")
    const { industries } = await this.fetchFilters(market, sector)
    // 响应乱序防护：板块/市场已再次变化则丢弃过期响应
    if (this.sectorTarget.value !== sector || this.marketTarget.value !== market) return
    this.renderOptions(this.industryTarget, industries, "")
    this.industryTarget.disabled = false
  }

  resetIndustry() {
    this.renderOptions(this.industryTarget, [], "")
    this.industryTarget.disabled = true
  }

  async fetchFilters(market, sector) {
    const key = `${market}|${sector || ""}`
    if (this.filterCache[key]) return this.filterCache[key]
    try {
      const res = await fetch(`/screener/filters?market=${encodeURIComponent(market)}&sector=${encodeURIComponent(sector || "")}`)
      const data = await res.json()
      this.filterCache[key] = data
      return data
    } catch (error) {
      console.error("加载筛选项失败:", error)
      return { sectors: [], industries: [] }
    }
  }

  renderOptions(select, items, selected, placeholder = null) {
    let html = placeholder ? `<option value="">${this.escapeHtml(placeholder)}</option>` : '<option value="">全部</option>'
    html += items.map((v) => `<option value="${this.escapeHtml(v)}" ${v === selected ? "selected" : ""}>${this.escapeHtml(v)}</option>`).join("")
    select.innerHTML = html
  }

  escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]))
  }

  // ---------- 勾选开关与输入框禁用联动 ----------

  toggleIndicator(event) {
    this.syncIndicator(event.target.dataset.key, event.target.checked)
  }

  syncIndicator(key, enabled) {
    this.indicatorInputTargets
      .filter((el) => el.name.startsWith(`${key}_`))
      .forEach((el) => { el.disabled = !enabled })
  }

  toggleGrowth() {
    this.syncGrowth()
  }

  syncGrowth() {
    const enabled = this.growthToggleTarget.checked
    const mode = this.growthModeSelect()?.value || "yoy"
    this.growthInputTargets.forEach((el) => {
      // 阈值输入框仅在「末年同比」模式下可用
      if (el.name === "growth_value") {
        el.disabled = !enabled || mode !== "yoy"
      } else {
        el.disabled = !enabled
      }
    })
  }

  growthModeSelect() {
    return this.growthInputTargets.find((el) => el.name === "growth_mode")
  }

  // ---------- 预设策略 ----------

  applyPreset(event) {
    const preset = JSON.parse(event.params.preset || "{}")
    Object.entries(preset).forEach(([key, value]) => {
      if (key.endsWith("_enabled")) {
        const base = key.replace("_enabled", "")
        const toggle = this.findToggle(base)
        if (toggle) {
          toggle.checked = !!value
          toggle.dispatchEvent(new Event("change"))
        }
        return
      }
      const el = this.element.querySelector(`[name="${key}"]`)
      if (el) {
        el.value = value
        // 预设改变市场时派发 change，联动刷新板块并重置行业
        if (key === "market") el.dispatchEvent(new Event("change"))
      }
    })
    // 预设未显式给出的指标行自动关闭，避免残留旧条件
    ;["roe", "gm", "npm"].forEach((base) => {
      if (`${base}_enabled` in preset) return
      const toggle = this.findToggle(base)
      if (toggle && toggle.checked) {
        toggle.checked = false
        toggle.dispatchEvent(new Event("change"))
      }
    })
    const growthToggle = this.growthToggleTarget
    if (!("growth_enabled" in preset) && growthToggle.checked) {
      growthToggle.checked = false
      growthToggle.dispatchEvent(new Event("change"))
    }
    this.syncGrowth()
  }

  findToggle(base) {
    if (base === "growth") return this.growthToggleTarget
    return this.indicatorToggleTargets.find((el) => el.dataset.key === base)
  }

  // ---------- 结果表渲染后默认展示最近年份 ----------

  frameLoaded() {
    // 等布局完成后把年份数据区滚到最右（末年）
    requestAnimationFrame(() => {
      this.scrollerTargets.forEach((el) => { el.scrollLeft = el.scrollWidth })
    })
  }

  // ---------- 结果表行交互 ----------

  // 同一只股票的多个指标行为一组，hover 时整组变色（rowspan 组无法用纯 CSS 实现）
  rowEnter(event) {
    this.setGroupHover(event.params.group, true)
  }

  rowLeave(event) {
    this.setGroupHover(event.params.group, false)
  }

  setGroupHover(id, on) {
    this.element.querySelectorAll(`tr[data-screener-group-param="${id}"] td`).forEach((cell) => {
      cell.style.backgroundColor = on ? "var(--color-bg-soft)" : ""
    })
  }

  openStock(event) {
    if (event.target.closest("a, button, select, input")) return
    // 行内拖选文本后 mouseup 也会派发 click，避免误开新标签页
    const selection = window.getSelection()
    if (selection && !selection.isCollapsed) return
    if (event.params.url) window.open(event.params.url, "_blank")
  }
}
