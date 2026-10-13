import { Controller } from "@hotwired/stimulus"

// 企业质量档案右侧悬浮目录：点击平滑滚动 + 滚动时高亮当前章节
// 生命周期由 Stimulus 管理，天然适配 Turbo（页面替换时 connect/disconnect 自动重绑）
export default class extends Controller {
  static targets = ["link"]

  connect() {
    // 顶部 sticky 导航栏占位高度，取自全站 Token（--spacing-hl-nav），与 CSS scroll-margin-top 同源
    this.navOffset = parseInt(
      getComputedStyle(document.documentElement).getPropertyValue("--spacing-hl-nav"), 10
    ) || 64
    this._onScroll = () => this._spy()
    window.addEventListener("scroll", this._onScroll, { passive: true })
    this._spy()
  }

  disconnect() {
    window.removeEventListener("scroll", this._onScroll)
  }

  // 点击目录项：平滑滚动到对应标题（阻止 hash 跳转，避免 Turbo 整页刷新）
  click(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.tocId
    const heading = document.getElementById(id)
    if (!heading) return

    const top = heading.getBoundingClientRect().top + window.scrollY - this.navOffset
    window.scrollTo({ top, behavior: "smooth" })
    history.replaceState(null, "", `#${id}`)
    this._activate(id)
  }

  // 滚动监听：找到视口上部最近的标题并高亮
  _spy() {
    let activeId = null
    for (const link of this.linkTargets) {
      const el = document.getElementById(link.dataset.tocId)
      if (el && el.getBoundingClientRect().top - this.navOffset <= 8) activeId = link.dataset.tocId
    }
    this._activate(activeId || this.linkTargets[0]?.dataset.tocId)
  }

  _activate(id) {
    this.linkTargets.forEach((link) => {
      link.classList.toggle("is-active", link.dataset.tocId === id)
    })
  }
}
