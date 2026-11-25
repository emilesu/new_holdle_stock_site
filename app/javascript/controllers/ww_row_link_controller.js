import { Controller } from "@hotwired/stimulus"

// 开窗观察列表：整行点击=新窗口打开个股页（对齐金字塔页 .stock-row 委托交互）
// 行内交互/标注元素（链接、按钮、data-no-open 的徽章与已收藏星标）不触发跳转，避免双开
export default class extends Controller {
  connect() {
    this.handler = (event) => {
      if (event.target.closest("a, form, button, [data-no-open]")) return
      const row = event.target.closest("[data-stock-url]")
      if (!row) return
      window.open(row.dataset.stockUrl, "_blank")
    }
    this.element.addEventListener("click", this.handler)
  }

  disconnect() {
    this.element.removeEventListener("click", this.handler)
  }
}
