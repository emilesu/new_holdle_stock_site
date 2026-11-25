import { Controller } from "@hotwired/stimulus"

// 全量视图检索模糊补全（2026-11-25 老板定：与导航栏同款，仅限A股 market=CN）
// 输入防抖请求 /stocks/autocomplete；选中项回填纯数字代码（同时命中 code 与 symbol）并提交筛选表单
export default class extends Controller {
  static targets = ["input", "list"]

  connect() {
    this.counter = 0
    this.items = []
    this.active = -1
    this.outsideHandler = (event) => {
      if (!this.element.contains(event.target)) this.hide()
    }
    document.addEventListener("click", this.outsideHandler, true)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("click", this.outsideHandler, true)
  }

  onFocus() { if (this.items.length) this.show() }

  onInput() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchSuggestions(), 200)
  }

  onKey(event) {
    if (event.key === "Escape") { this.hide(); return }
    if (!this.items.length) return
    if (event.key === "ArrowDown") { event.preventDefault(); this.move(1) }
    else if (event.key === "ArrowUp") { event.preventDefault(); this.move(-1) }
    else if (event.key === "Enter" && this.active >= 0) { event.preventDefault(); this.select(this.items[this.active]) }
  }

  async fetchSuggestions() {
    const query = this.inputTarget.value.trim()
    if (query.length < 1) { this.hide(); return }
    const requestId = ++this.counter
    try {
      const response = await fetch(`/stocks/autocomplete?q=${encodeURIComponent(query)}&market=CN`)
      const data = await response.json()
      if (requestId !== this.counter) return
      this.items = data
      this.render()
    } catch (e) {
      // 网络失败静默降级：手输 + 「应用」照常可用
    }
  }

  render() {
    this.active = -1
    this.listTarget.innerHTML = ""
    if (!this.items.length) { this.hide(); return }
    this.items.forEach((item) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "w-full text-left px-3 py-1.5 text-hl-13 hover:bg-bg-mute flex items-center justify-between gap-2"
      const name = document.createElement("span")
      name.className = "truncate text-ink"
      name.textContent = item.name
      const meta = document.createElement("span")
      meta.className = "text-hl-11 text-muted-3 font-mono shrink-0"
      meta.textContent = item.symbol
      btn.append(name, meta)
      btn.addEventListener("click", () => this.select(item))
      this.listTarget.append(btn)
    })
    this.show()
  }

  select(item) {
    // 去交易所前缀的纯数字代码：全量检索对 code（sh600036）与 symbol（600036.SH）双向命中
    this.inputTarget.value = item.symbol.replace(/^(SH|SZ|BJ)/, "")
    this.hide()
    this.inputTarget.form.requestSubmit()
  }

  move(delta) {
    this.active = Math.min(Math.max(this.active + delta, -1), this.items.length - 1)
    Array.from(this.listTarget.children).forEach((el, i) => el.classList.toggle("bg-bg-mute", i === this.active))
  }

  show() { this.listTarget.classList.remove("hidden") }

  hide() {
    this.listTarget.classList.add("hidden")
    this.items = []
    this.active = -1
  }
}
