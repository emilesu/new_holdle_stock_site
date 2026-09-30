import { Controller } from "@hotwired/stimulus"

// 爬虫执行进度自动刷新
//
// 挂在 turbo-frame 上：帧内存在 data-crawler-active="true" 标记时，每 5 秒 reload() 一次帧；
// 标记为 false（没有 running 任务）时停止轮询，避免后台常驻请求。
//
// 注意：
//  1. Turbo 的 frame.reload() 是「记住 src → 清空 src → 重新赋回 src」，帧没有 src 时
//     不会发起任何请求；因此视图仅在 @crawler_active 为真时才给帧渲染 src，
//     空闲状态下本控制器不会（也无法）产生请求。
//  2. 后台 layout 为登录态，Turbo 快照缓存已禁用（turbo-cache-control: no-cache），
//     turbo:before-cache 不会派发，所以清理逻辑靠 disconnect + 定时器内的存活检查兜底。
//  3. 帧内容被替换时帧元素本身不变（Turbo 只换子节点），data-crawler-active 标记在帧内部，
//     故每次 tick 重新读取；替换后派发的 turbo:frame-load 用于重新评估是否需要继续轮询。
const POLL_INTERVAL = 5000

export default class extends Controller {
  connect() {
    this.timer = null
    this._boundFrameLoad = this.sync.bind(this)
    this.element.addEventListener("turbo:frame-load", this._boundFrameLoad)
    this.sync()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this._boundFrameLoad)
    this.stop()
  }

  sync() {
    if (this.active()) {
      this.start()
    } else {
      this.stop()
    }
  }

  active() {
    const marker = this.element.querySelector("[data-crawler-active]")
    return marker?.dataset.crawlerActive === "true"
  }

  start() {
    if (this.timer) return
    this.timer = setInterval(() => this.reload(), POLL_INTERVAL)
  }

  stop() {
    if (!this.timer) return
    clearInterval(this.timer)
    this.timer = null
  }

  reload() {
    // 元素已被 Turbo 移除或任务已结束 → 停止轮询
    if (!this.element.isConnected || !this.active()) {
      this.stop()
      return
    }
    this.element.reload()
  }
}
