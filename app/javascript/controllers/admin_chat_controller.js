import { Controller } from "@hotwired/stimulus"

// 后台会话详情页：打开或回复重定向后，滚动到会话卡片底部展示最新内容
export default class extends Controller {
  connect() {
    requestAnimationFrame(() => this.element.scrollIntoView({ block: "end" }))
  }
}
