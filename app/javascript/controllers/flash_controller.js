import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
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
