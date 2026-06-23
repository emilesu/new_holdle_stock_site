import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "arrow"]

  connect() {
    this.open = false
    this.clickOutsideHandler = this.clickOutside.bind(this)
    this.keydownHandler = this.keydown.bind(this)
  }

  disconnect() {
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
    this.menuTarget.offsetHeight
    this.menuTarget.classList.add("hl-dropdown-open")
    this.setAriaExpanded(true)
    this.rotateArrow(true)
    this.addGlobalListeners()
  }

  close() {
    if (!this.open) return
    this.open = false
    this.menuTarget.classList.remove("hl-dropdown-open")
    this.menuTarget.classList.add("hl-dropdown-closing")
    this.setAriaExpanded(false)
    this.rotateArrow(false)
    setTimeout(() => {
      this.menuTarget.classList.add("hidden")
      this.menuTarget.classList.remove("hl-dropdown-closing")
    }, 150)
    this.removeGlobalListeners()
  }

  setAriaExpanded(expanded) {
    const btn = this.element.querySelector("button")
    if (btn) btn.setAttribute("aria-expanded", expanded)
  }

  rotateArrow(open) {
    if (this.hasArrowTarget) {
      this.arrowTarget.classList.toggle("rotate-180", open)
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

  addGlobalListeners() {
    document.addEventListener("click", this.clickOutsideHandler)
    document.addEventListener("keydown", this.keydownHandler)
  }

  removeGlobalListeners() {
    document.removeEventListener("click", this.clickOutsideHandler)
    document.removeEventListener("keydown", this.keydownHandler)
  }
}