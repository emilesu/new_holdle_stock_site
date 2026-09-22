import { Controller } from "@hotwired/stimulus"

// 股票筛选页交互：预设策略一键填充表单、盈利指标/净利润条件启用开关联动输入框禁用状态
// 禁用的表单控件不会被 GET 提交，天然实现「留空即不启用」
export default class extends Controller {
  static targets = ["form", "indicatorToggle", "indicatorInput", "growthToggle", "growthInput"]

  connect() {
    // Turbo 缓存恢复后重新同步一次禁用状态
    this.indicatorToggleTargets.forEach((el) => this.syncIndicator(el.dataset.key, el.checked))
    this.syncGrowth()
  }

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

  // 预设策略：data-screener-preset-param 为 JSON，键为表单 name 或 xxx_enabled 开关
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
      if (el) el.value = value
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
}
