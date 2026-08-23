import { Controller } from "@hotwired/stimulus"

// 横滑卡片组：CSS scroll-snap 承载触摸滑动，JS 只做桌面箭头翻页 + 圆点指示器联动。
// 用法：data-controller="carousel"，卡片加 data-carousel-card，圆点加 data-index
export default class extends Controller {
  static targets = ["track", "dot", "prevBtn", "nextBtn"]

  connect() {
    this.trackTarget.addEventListener("scroll", this._onScroll, { passive: true })
    this._sync()
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this._onScroll)
  }

  _onScroll = () => {
    this._sync()
  }

  prev() {
    this._scrollBy(-1)
  }

  next() {
    this._scrollBy(1)
  }

  select(event) {
    this._scrollTo(Number(event.currentTarget.dataset.index))
  }

  _scrollBy(offset) {
    this._scrollTo(this._currentIndex() + offset)
  }

  _scrollTo(index) {
    const track = this.trackTarget
    if (track.children.length === 0) return
    const max = track.children.length - 1
    const target = Math.max(0, Math.min(index, max))
    // offsetLeft 天然包含卡片间 gap（offsetWidth 累乘会累计偏差，scrollIntoView 在 snap 容器兼容性差）
    track.scrollTo({ left: track.children[target].offsetLeft, behavior: "smooth" })
  }

  _currentIndex() {
    const track = this.trackTarget
    let closest = 0
    let minDist = Infinity
    Array.from(track.children).forEach((child, i) => {
      const dist = Math.abs(child.offsetLeft - track.scrollLeft)
      if (dist < minDist) {
        minDist = dist
        closest = i
      }
    })
    return closest
  }

  _sync() {
    const total = this.trackTarget.children.length
    if (total === 0) return
    const current = this._currentIndex()

    this.dotTargets.forEach((dot, i) => {
      dot.classList.toggle("bg-ink", i === current)
      dot.classList.toggle("bg-line", i !== current)
    })

    if (this.hasPrevBtnTarget) this.prevBtnTarget.disabled = current === 0
    if (this.hasNextBtnTarget) this.nextBtnTarget.disabled = current >= total - 1
  }
}
