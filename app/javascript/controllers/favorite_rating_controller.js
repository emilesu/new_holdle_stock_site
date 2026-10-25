import { Controller } from "@hotwired/stimulus"

// 收藏星级：悬停 / 聚焦预览填充，提交中禁用交互防连点。
// 服务端已按当前星级渲染初始填充状态，本控制器只做增强，不改变提交逻辑。
export default class extends Controller {
  static targets = ["star"]
  // activeClass 由服务端按市场主题色下发（A股绿 / 港股琥珀 / 美股蓝）
  static values = { rating: Number, activeClass: String }

  connect() {
    this.currentRating = this.ratingValue
    // 请求失败时恢复可点击；成功时组件会被 turbo_stream 整体替换，无需处理
    this.submitEndHandler = () => this.enable()
    this.element.addEventListener("turbo:submit-end", this.submitEndHandler)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.submitEndHandler)
  }

  // 预览：把 rating 及以下的星点亮
  preview(event) {
    this.paint(Number(event.currentTarget.dataset.rating))
  }

  // 移出 / 失焦：恢复到服务端下发的当前星级
  reset() {
    this.paint(this.currentRating)
  }

  // 不能用 disabled 禁用按钮：提交事件里禁用 submitter 会让它的 name=rating
  // 不进入表单数据，导致每次点击都按「缺参」回落成默认星级
  submitting() {
    this.element.setAttribute("aria-busy", "true")
    this.element.classList.add("opacity-60", "pointer-events-none")
  }

  enable() {
    this.element.removeAttribute("aria-busy")
    this.element.classList.remove("opacity-60", "pointer-events-none")
  }

  paint(rating) {
    // 按空白拆分：服务端若下发多个 class 也能逐个 toggle（classList 不接受整串）
    const activeClass = this.activeClassValue || "text-blue-600"
    const activeTokens = activeClass.split(/\s+/).filter(Boolean)
    this.starTargets.forEach((star) => {
      const active = Number(star.dataset.rating) <= rating
      activeTokens.forEach((token) => star.classList.toggle(token, active))
      star.classList.toggle("text-muted-6", !active)
    })
  }
}
