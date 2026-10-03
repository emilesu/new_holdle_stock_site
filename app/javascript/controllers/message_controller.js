import { Controller } from "@hotwired/stimulus"

// 会话页（/messages）控制器：
// - 进入/刷新页面自动定位到最新消息（滚动到聊天卡片底部，输入栏贴视口底、footer 不占屏）
// - 「加载更早消息」按钮：fetch earlier 游标页 → turbo_stream prepend，并做滚动补偿保持视觉位置
// - 发送表单：turbo:submit-end 成功后滚回最新消息处（textarea 由服务端 replace 表单重置）
export default class extends Controller {
  static targets = ["contentInput"]

  connect() {
    this.scrollToLatest()
  }

  // 以聊天卡片为锚滚动：卡片底边对齐视口底边；rAF 等待布局完成，避免滚到文档底部或停在顶部
  scrollToLatest() {
    const card = document.getElementById("message_card")
    if (!card) return
    requestAnimationFrame(() => card.scrollIntoView({ block: "end" }))
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
    if (e.detail.success) this.scrollToLatest()
  }
}
