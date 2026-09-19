import { Controller } from "@hotwired/stimulus"

// 财务表格：默认横向滚动到最右，让最近年份与右侧季报同比列一开始就可见。
// 用法：data-controller="financial-table"，滚动容器加 data-financial-table-target="scroll"
export default class extends Controller {
  static targets = ["scroll"]

  connect() {
    this.scrollTargets.forEach((container) => {
      container.scrollLeft = container.scrollWidth
    })
  }
}
