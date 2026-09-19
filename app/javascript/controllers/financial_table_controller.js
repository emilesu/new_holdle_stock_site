import { Controller } from "@hotwired/stimulus"

// 财务表格：默认横向滚动到最右，让最近年份与右侧季报同比列一开始就可见；
// 并给整行标记当前鼠标所在的区域（年报区 / 季报区），让两侧 hover 高亮互不联动。
// 用法：data-controller="financial-table"，滚动容器加 data-financial-table-target="scroll"
// 与 data-action="mouseover->financial-table#zoneEnter mouseleave->financial-table#zoneLeave"；
// 单元格加 data-hover-zone="annual" 或 "quarter"，行加 .financial-row。
// 注意：mouseleave 只在离开整个滚动容器时触发，跨行移动不会触发，所以清标记主要靠 zoneEnter。
export default class extends Controller {
  static targets = ["scroll"]

  connect() {
    this.scrollTargets.forEach((container) => {
      container.scrollLeft = container.scrollWidth
    })
  }

  // 鼠标进入某个区域时，把该区域记到整行上（CSS 据此只高亮该区域），并清掉上一行的标记
  zoneEnter(event) {
    const row = event.target.closest(".financial-row")
    const cell = row && event.target.closest("[data-hover-zone]")

    // 移到表头、空白处等非数据区域时，直接清空当前行标记
    if (!row || !cell) {
      this.clearActiveRow()
      return
    }

    if (row !== this.activeRow) {
      this.clearActiveRow()
      this.activeRow = row
    }

    row.dataset.hoverZoneActive = cell.dataset.hoverZone
  }

  // 鼠标完全离开滚动容器时清空标记
  zoneLeave() {
    this.clearActiveRow()
  }

  clearActiveRow() {
    if (!this.activeRow) return

    delete this.activeRow.dataset.hoverZoneActive
    this.activeRow = null
  }
}
