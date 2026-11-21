import { Controller } from "@hotwired/stimulus"

// 对比栏：次新股过滤开关（localStorage 缓存）+ 滚动分批加载
// 开关口径与金字塔页一致：仅 hide 写参数/缓存，show 为默认不写

const STORAGE_KEY = "comparison_new_listing_v1"
const STORAGE_TTL = 7 * 24 * 60 * 60 * 1000

export default class extends Controller {
  static targets = ["list", "sentinel", "scroll", "toggle"]
  static values = { url: String, nextPage: Number, hasMore: Boolean }

  connect() {
    this.loading = false
    // epoch 代际标记：切换过滤时递增，在途请求完成后发现代际已变即丢弃结果，
    // 防止旧口径的分页/重载响应污染切换后的新列表
    this.epoch = 0
    // appliedListing：当前列表实际渲染所用的过滤口径；
    // 分页请求始终按它取数，切换失败时开关回退到它，保证列表与请求口径一致
    // 开关语义：checked（开）= show，unchecked（关）= hide
    this.appliedListing = this.toggleTarget.checked ? "show" : "hide"
    // 先恢复缓存（内部会置 loading 阻断分页），再建立哨兵监听
    this.restoreSelection()
    this.observeSentinel()
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  // ---------- 次新股过滤开关 ----------

  toggleChange() {
    const value = this.toggleTarget.checked ? "show" : "hide"
    if (value === this.appliedListing) return
    this.saveSelection(value)
    this.reloadFirstPage(value)
  }

  saveSelection(value) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ new_listing: value, ts: Date.now() }))
    } catch (e) { /* 无痕模式等存储不可用时静默忽略 */ }
  }

  // URL 显式带 new_listing 时（分享/收藏链接）以链接为准，不用缓存覆盖
  restoreSelection() {
    if (new URLSearchParams(window.location.search).has("new_listing")) return

    let saved = null
    try {
      saved = JSON.parse(localStorage.getItem(STORAGE_KEY))
    } catch (e) {
      return
    }
    if (!saved || Date.now() - (saved.ts || 0) > STORAGE_TTL) return
    if (saved.new_listing !== "hide" || !this.toggleTarget.checked) return

    this.toggleTarget.checked = false
    this.reloadFirstPage("hide")
  }

  // 切换过滤后整体替换第一批，并重置分页状态
  async reloadFirstPage(listing) {
    const epoch = ++this.epoch
    if (this.observer) this.observer.disconnect()

    // 阻断切换期间新发起的分页；在途分页由各自的 epoch 校验丢弃
    this.loading = true
    let ok = false
    try {
      const data = await this.fetchPage(1, listing)
      if (this.epoch === epoch) {
        this.listTarget.innerHTML = data.html ||
          '<div class="py-6 text-center text-hl-13 text-muted-3">无符合条件的对比股票</div>'
        this.hasMoreValue = data.has_more
        this.nextPageValue = data.next_page || 2
        ok = true
      }
    } catch (error) {
      console.error("对比栏切换过滤失败", error)
    }

    // 已有更新的切换在途/完成：由那一次负责复位 loading 与重建哨兵，本次结果作废
    if (this.epoch !== epoch) return

    this.loading = false
    if (ok) {
      this.appliedListing = listing
    } else {
      // 失败：列表仍是旧口径，开关回退，避免分页请求与列表内容口径不一致
      this.toggleTarget.checked = this.appliedListing === "show"
    }

    this.observeSentinel()
  }

  // ---------- 滚动分批加载 ----------

  observeSentinel() {
    if (this.observer) this.observer.disconnect()
    if (!this.hasMoreValue) {
      this.sentinelTarget.classList.add("hidden")
      return
    }

    this.sentinelTarget.textContent = "加载更多…"
    this.sentinelTarget.classList.remove("hidden")
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) this.loadNext()
      },
      { root: this.scrollTarget, rootMargin: "200px 0px" }
    )
    this.observer.observe(this.sentinelTarget)
  }

  async loadNext() {
    if (this.loading || !this.hasMoreValue) return

    this.loading = true
    const epoch = this.epoch
    this.sentinelTarget.textContent = "加载更多…"

    let loaded = false
    try {
      const data = await this.fetchPage(this.nextPageValue, this.appliedListing)
      // 请求期间发生过过滤切换：旧口径结果直接丢弃，loading 复位交由切换流程处理
      if (this.epoch !== epoch) return

      this.listTarget.insertAdjacentHTML("beforeend", data.html)
      this.hasMoreValue = data.has_more
      if (data.next_page) this.nextPageValue = data.next_page
      loaded = true

      // 全部加载完：断开监听并隐藏哨兵（节点保留，切换过滤后还需复用）
      if (!this.hasMoreValue) {
        if (this.observer) this.observer.disconnect()
        this.sentinelTarget.classList.add("hidden")
      }
    } catch (error) {
      if (this.epoch !== epoch) return
      console.error("对比栏加载失败", error)
      // 失败后停止自动重试，避免接口异常时形成无限请求；用户滚出再滚回可重新触发
      this.sentinelTarget.textContent = "加载失败，请滚动重试"
    } finally {
      if (this.epoch === epoch) this.loading = false
    }

    // 仅在本次请求成功后继续：追加后哨兵仍在可视范围内（首屏不足一屏）时继续加载
    if (loaded && this.hasMoreValue && this.sentinelVisible()) this.loadNext()
  }

  // 组装请求：滚动分页与切换过滤共用，hide 时显式带参（与金字塔页 URL 约定一致）
  fetchPage(page, listing) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("page", page)
    if (listing === "hide") url.searchParams.set("new_listing", "hide")

    return fetch(url, { headers: { Accept: "application/json" } }).then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      return response.json()
    })
  }

  sentinelVisible() {
    const rootRect = this.scrollTarget.getBoundingClientRect()
    const sentinelRect = this.sentinelTarget.getBoundingClientRect()
    return sentinelRect.top <= rootRect.bottom + 200
  }
}
