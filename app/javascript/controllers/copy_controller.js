import { Controller } from "@hotwired/stimulus"

// 一键复制：data-controller="copy"，source 为待复制内容（value 或 textContent）
export default class extends Controller {
  static targets = ["source"]

  copy(event) {
    const btn = event.currentTarget
    const text = this.sourceTarget.value ?? this.sourceTarget.textContent
    // 首次点击时缓存按钮原始文案，防止连点把「已复制 ✓」当 original
    if (!btn.dataset.originalLabel) {
      btn.dataset.originalLabel = btn.dataset.copyLabel || btn.textContent
    }

    navigator.clipboard.writeText(text).then(() => {
      this._feedback(btn, "已复制 ✓")
    }).catch(() => {
      this._feedback(btn, "复制失败，请手动选择")
    })
  }

  _feedback(btn, msg) {
    const original = btn.dataset.originalLabel || btn.textContent
    btn.textContent = msg
    setTimeout(() => { btn.textContent = original }, 1600)
  }
}
