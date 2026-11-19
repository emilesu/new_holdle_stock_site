import { Controller } from "@hotwired/stimulus"

// 对比栏滚动分批加载：监听列表底部哨兵，进入可视区域时请求下一批
export default class extends Controller {
  static targets = ["list", "sentinel"]
  static values = { url: String, nextPage: Number, hasMore: Boolean }

  connect() {
    this.loading = false
    if (!this.hasMoreValue || !this.hasSentinelTarget) return

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) this.loadNext()
      },
      { root: this.element, rootMargin: "200px 0px" }
    )
    this.observer.observe(this.sentinelTarget)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  async loadNext() {
    if (this.loading || !this.hasMoreValue) return

    this.loading = true
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("page", this.nextPageValue)

      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const data = await response.json()
      this.listTarget.insertAdjacentHTML("beforeend", data.html)
      this.hasMoreValue = data.has_more
      if (data.next_page) this.nextPageValue = data.next_page

      if (!this.hasMoreValue) {
        this.observer.disconnect()
        if (this.hasSentinelTarget) this.sentinelTarget.remove()
      }
    } catch (error) {
      console.error("对比栏加载失败", error)
    } finally {
      this.loading = false
    }

    // 追加后哨兵仍在可视范围内（首屏不足一屏）时继续加载
    if (this.hasMoreValue && this.sentinelVisible()) this.loadNext()
  }

  sentinelVisible() {
    if (!this.hasSentinelTarget) return false

    const rootRect = this.element.getBoundingClientRect()
    const sentinelRect = this.sentinelTarget.getBoundingClientRect()
    return sentinelRect.top <= rootRect.bottom + 200
  }
}
