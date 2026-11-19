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
    if (this.hasSentinelTarget) this.sentinelTarget.textContent = "加载更多…"

    let loaded = false
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("page", this.nextPageValue)

      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const data = await response.json()
      this.listTarget.insertAdjacentHTML("beforeend", data.html)
      this.hasMoreValue = data.has_more
      if (data.next_page) this.nextPageValue = data.next_page
      loaded = true

      if (!this.hasMoreValue) {
        this.observer.disconnect()
        if (this.hasSentinelTarget) this.sentinelTarget.remove()
      }
    } catch (error) {
      console.error("对比栏加载失败", error)
      // 失败后停止自动重试，避免接口异常时形成无限请求；用户滚出再滚回可重新触发
      if (this.hasSentinelTarget) this.sentinelTarget.textContent = "加载失败，请滚动重试"
    } finally {
      this.loading = false
    }

    // 仅在本次请求成功后继续：追加后哨兵仍在可视范围内（首屏不足一屏）时继续加载
    if (loaded && this.hasMoreValue && this.sentinelVisible()) this.loadNext()
  }

  sentinelVisible() {
    if (!this.hasSentinelTarget) return false

    const rootRect = this.element.getBoundingClientRect()
    const sentinelRect = this.sentinelTarget.getBoundingClientRect()
    return sentinelRect.top <= rootRect.bottom + 200
  }
}
