import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.showPanel(this.data.get("default") || "quick")
  }

  switchTab(event) {
    event.preventDefault()
    const tabId = event.currentTarget.dataset.tab
    if (tabId) {
      this.showPanel(tabId)
    }
  }

  showPanel(tabId) {
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === tabId) {
        tab.classList.add("login-tab-btn-active")
      } else {
        tab.classList.remove("login-tab-btn-active")
      }
    })

    this.panelTargets.forEach(panel => {
      if (panel.id === `tab-${tabId}`) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
  }
}