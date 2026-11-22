import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    // delay 为 0 表示不自动消失：错误类提示（alert）必须留在页面上直到用户处理，
    // 否则长页面里一闪而过，用户体感就是「点了没反应」
    if (this.delayValue > 0) {
      this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
    clearTimeout(this.removeTimer)
  }

  dismiss() {
    if (this.dismissed) return
    this.dismissed = true
    clearTimeout(this.timeout)
    this.element.style.transition = "opacity 0.3s ease-out"
    this.element.style.opacity = "0"
    this.removeTimer = setTimeout(() => {
      const host = this.element.parentElement
      this.element.remove()
      // 只移除布局中显式标记 data-flash-host 的专用 wrapper（仅装提示框）：
      // 提示全部移除后若留着，其 pt-4 内边距会在导航栏与正文之间留下空隙
      if (host && host.hasAttribute("data-flash-host") && host.children.length === 0) {
        host.remove()
      }
    }, 300)
  }
}
