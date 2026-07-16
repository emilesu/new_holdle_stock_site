import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "buttonIcon"]

  connect() {
    this.open = false
    this._boundClickOutside = this.clickOutside.bind(this)
    this._boundKeydown = this.keydown.bind(this)
  }

  disconnect() {
    // 由 layout 中 turbo:before-cache handler 负责关闭菜单，这里只清理全局状态
    this.open = false
    this.removeGlobalListeners()
  }

  toggle(event) {
    event.stopPropagation()
    if (this.open) {
      this.close()
    } else {
      this.openMenu()
    }
  }

  openMenu() {
    this.open = true
    this.menuTarget.classList.remove("hidden")
    requestAnimationFrame(() => {
      this.menuTarget.classList.add("mobile-menu-open")
    })
    this.swapIcon(true)
    document.addEventListener("click", this._boundClickOutside)
    document.addEventListener("keydown", this._boundKeydown)
  }

  close() {
    if (!this.open) return
    this.open = false
    this.menuTarget.classList.remove("mobile-menu-open")
    this.swapIcon(false)
    setTimeout(() => {
      this.menuTarget.classList.add("hidden")
    }, 200)
    this.removeGlobalListeners()
  }

  swapIcon(open) {
    if (!this.hasButtonIconTarget) return
    if (open) {
      this.buttonIconTarget.innerHTML =
        '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>'
    } else {
      this.buttonIconTarget.innerHTML =
        '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/>'
    }
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  removeGlobalListeners() {
    document.removeEventListener("click", this._boundClickOutside)
    document.removeEventListener("keydown", this._boundKeydown)
  }
}