import { Controller } from "@hotwired/stimulus"

// 收藏星级：悬停 / 聚焦预览填充，提交中禁用交互防连点。
// 服务端已按当前星级渲染初始填充状态，本控制器只做增强，不改变提交逻辑。
export default class extends Controller {
  static targets = ["star"]
  static values = { rating: Number }

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
    this.starTargets.forEach((star) => {
      const active = Number(star.dataset.rating) <= rating
      star.classList.toggle("text-amber-500", active)
      star.classList.toggle("text-muted-6", !active)
    })
  }
}
