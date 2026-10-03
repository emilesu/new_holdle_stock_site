import { Controller } from "@hotwired/stimulus"

// 会话页（/messages）控制器：
// - 进入页面自动滚到最新消息（窗口级滚动，整页即会话流）
// - 「加载更早消息」按钮：fetch earlier 游标页 → turbo_stream prepend，并做滚动补偿保持视觉位置
// - 发送表单：turbo:submit-end 成功后滚回底部（textarea 由服务端 replace 表单重置）
export default class extends Controller {
  static targets = ["contentInput"]

  connect() {
    this.scrollToBottom()
  }

  scrollToBottom() {
    window.scrollTo({ top: document.documentElement.scrollHeight })
  }

  loadEarlier(e) {
    const btn = e.currentTarget
    const beforeAt = btn.dataset.beforeAt
    const beforeId = btn.dataset.beforeId
    if (!beforeAt || !beforeId) return
    btn.disabled = true

    // 记录 prepend 前的文档高度与滚动位置，插入更早消息后补偿，避免视觉跳动
    const prevHeight = document.documentElement.scrollHeight
    const prevScroll = window.scrollY

    fetch(`/messages/earlier?before_at=${encodeURIComponent(beforeAt)}&before_id=${beforeId}`, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    }).then(r => r.text()).then(html => {
      if (!html) return
      Turbo.renderStreamMessage(html)
      requestAnimationFrame(() => {
        window.scrollTo({ top: document.documentElement.scrollHeight - prevHeight + prevScroll })
      })
    }).finally(() => {
      btn.disabled = false
    })
  }

  afterSubmit(e) {
    if (e.detail.success) this.scrollToBottom()
  }
}
