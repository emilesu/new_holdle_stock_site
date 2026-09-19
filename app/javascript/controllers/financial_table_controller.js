import { Controller } from "@hotwired/stimulus"

// 财务表格：默认横向滚动到最右，让最近年份与右侧季报同比列一开始就可见；
// 并给整行标记当前鼠标所在的区域（年报区 / 季报区），让两侧 hover 高亮互不联动。
// 用法：data-controller="financial-table"，滚动容器加 data-financial-table-target="scroll"
// 与 data-action="mouseover->financial-table#zoneEnter mouseleave->financial-table#zoneLeave"；
// 单元格加 data-hover-zone="annual" 或 "quarter"，行加 .financial-row。
// 离开用 mouseleave（只在真正离开滚动容器时触发一次、不冒泡），比 mouseout 跨容器时可靠。
export default class extends Controller {
  static targets = ["scroll"]

  connect() {
    this.scrollTargets.forEach((container) => {
      container.scrollLeft = container.scrollWidth
    })
  }

  // 鼠标进入某个区域时，把该区域记到整行上（CSS 据此只高亮该区域）
  zoneEnter(event) {
    const cell = event.target.closest("[data-hover-zone]")
    const row = event.target.closest(".financial-row")
    if (!cell || !row) return

    row.dataset.hoverZoneActive = cell.dataset.hoverZone
  }

  // 鼠标完全离开滚动容器时，清空容器内所有行的区域标记
  zoneLeave(event) {
    this.scrollTargets.forEach((container) => {
      container.querySelectorAll(".financial-row").forEach((row) => {
        delete row.dataset.hoverZoneActive
      })
    })
  }
}
