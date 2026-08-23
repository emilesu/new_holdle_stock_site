import { Controller } from "@hotwired/stimulus"

// 宣传视频：封面占位 → 点击注入 B站 iframe（懒加载，不占首屏）。
// videoUrlValue 为空时（视频未发布）播放按钮不渲染，仅显示「制作中」占位。
export default class extends Controller {
  static targets = ["cover", "player"]
  static values = { videoUrl: String }

  play() {
    if (!this.videoUrlValue) return
    if (this.playerTarget.children.length > 0) return // 幂等：已注入过 iframe 不再重复追加

    const iframe = document.createElement("iframe")
    iframe.src = this.videoUrlValue
    iframe.className = "absolute inset-0 w-full h-full"
    iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
    iframe.allowFullscreen = true
    iframe.setAttribute("frameborder", "0")
    iframe.scrolling = "no"
    iframe.title = "HOLDLE AI 投研助手宣传视频"

    this.playerTarget.appendChild(iframe)
    this.playerTarget.classList.remove("hidden")
    this.coverTarget.classList.add("hidden")
  }
}
