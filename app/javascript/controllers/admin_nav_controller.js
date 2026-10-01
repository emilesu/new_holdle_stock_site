import { Controller } from "@hotwired/stimulus"

// 管理后台顶栏分组下拉：同一时刻只展开一个分组，点击外部 / Esc 收起
// 监听器挂在 document 上，Stimulus disconnect（Turbo 整页替换时触发）负责清理
export default class extends Controller {
  connect() {
    this.openDropdown = null
    this.clickOutsideHandler = this.clickOutside.bind(this)
    this.keydownHandler = this.keydown.bind(this)
    document.addEventListener("click", this.clickOutsideHandler)
    document.addEventListener("keydown", this.keydownHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
    document.removeEventListener("keydown", this.keydownHandler)
    if (this.closeTimer) clearTimeout(this.closeTimer)
    this.openDropdown = null
  }

  toggle(event) {
    event.stopPropagation()
    const dropdown = event.currentTarget.parentElement
    if (this.openDropdown === dropdown) {
      this.closeAll()
    } else {
      this.closeAll()
      this.open(dropdown)
    }
  }

  open(dropdown) {
    // 取消可能仍在等待的关闭动画，避免旧 timeout 把刚展开的菜单重新 hidden
    if (this.closeTimer) {
      clearTimeout(this.closeTimer)
      this.closeTimer = null
    }
    this.openDropdown = dropdown
    const menu = dropdown.querySelector("[data-role='menu']")
    const arrow = dropdown.querySelector("[data-role='arrow']")
    menu.classList.remove("hidden", "hl-dropdown-closing")
    menu.offsetHeight // 强制 reflow，触发过渡动画
    menu.classList.add("hl-dropdown-open")
    arrow.classList.add("rotate-180")
    dropdown.querySelector("button").setAttribute("aria-expanded", "true")
  }

  close(dropdown) {
    const menu = dropdown.querySelector("[data-role='menu']")
    const arrow = dropdown.querySelector("[data-role='arrow']")
    menu.classList.remove("hl-dropdown-open")
    menu.classList.add("hl-dropdown-closing")
    arrow.classList.remove("rotate-180")
    dropdown.querySelector("button").setAttribute("aria-expanded", "false")
    this.closeTimer = setTimeout(() => {
      menu.classList.add("hidden")
      menu.classList.remove("hl-dropdown-closing")
      this.closeTimer = null
    }, 150)
  }

  closeAll() {
    if (this.openDropdown) this.close(this.openDropdown)
    this.openDropdown = null
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closeAll()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.closeAll()
    }
  }
}
