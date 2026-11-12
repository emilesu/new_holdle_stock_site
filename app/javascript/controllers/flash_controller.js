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
    this.removeTimer = setTimeout(() => this.element.remove(), 300)
  }
}
