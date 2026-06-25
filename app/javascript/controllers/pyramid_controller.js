import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { stockId: Number }

  recalculate(event) {
    const button = event.currentTarget
    const stockId = this.stockIdValue
    const originalText = button.textContent

    button.disabled = true
    button.textContent = '计算中...'

    fetch(`/admin/stocks/${stockId}/recalculate_pyramid`, {
      method: 'POST',
      headers: {
        'Accept': 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
    .then(response => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      return response.text()
    })
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
    .catch(error => {
      console.error('计算失败:', error)
      button.textContent = '计算失败'
      setTimeout(() => {
        button.textContent = originalText
        button.disabled = false
      }, 2000)
    })
  }
}