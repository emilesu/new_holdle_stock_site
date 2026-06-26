import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { stockId: Number }

  recalculate(event) {
    event.stopPropagation()
    const button = event.currentTarget
    const stockId = this.stockIdValue
    const originalText = button.textContent.trim()
    const row = this.element

    const scoreCell = row.querySelector("td:nth-child(7) div")
    const oldScore = scoreCell ? scoreCell.textContent.trim() : "?"

    console.log("[Pyramid] 重新计算: stockId=" + stockId + ", oldScore=" + oldScore + ", url=/admin/stocks/" + stockId + "/recalculate_pyramid")

    button.disabled = true
    button.textContent = "计算中..."

    const csrfToken = document.querySelector("meta[name=\"csrf-token\"]")?.content
    if (!csrfToken) {
      console.warn("[Pyramid] CSRF token not found in page meta tags - request may fail")
    }

    row.classList.add("bg-yellow-50")
    setTimeout(() => row.classList.remove("bg-yellow-50"), 500)

    fetch("/admin/stocks/" + stockId + "/recalculate_pyramid", {
      method: "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
        "X-CSRF-Token": csrfToken
      }
    })
    .then(response => {
      console.log("[Pyramid] 响应状态: " + response.status + " " + response.statusText)
      if (!response.ok) throw new Error("HTTP " + response.status)
      return response.text()
    })
    .then(html => {
      console.log("[Pyramid] 收到 Turbo Stream HTML (" + html.length + " chars)")
      const turbo = window.Turbo || Turbo
      turbo.renderStreamMessage(html)
      setTimeout(() => {
        this._flashRow(stockId, oldScore)
      }, 100)
    })
    .catch(error => {
      console.error("[Pyramid] 计算失败:", error)
      button.textContent = "计算失败"
      row.classList.add("bg-red-50")
      setTimeout(() => {
        button.textContent = originalText
        button.disabled = false
        row.classList.remove("bg-red-50")
      }, 3000)
    })
  }

  _flashRow(stockId, oldScore) {
    const newRow = document.getElementById("stock-" + stockId)
    if (!newRow) {
      console.warn("[Pyramid] 未找到 stock-" + stockId + " 行")
      return
    }

    const newScoreCell = newRow.querySelector("td:nth-child(7) div")
    const newScore = newScoreCell ? newScoreCell.textContent.trim() : "?"

    if (oldScore !== "?" && newScore !== "?" && oldScore !== newScore) {
      console.log("[Pyramid] 分数变化: " + oldScore + " -> " + newScore)
      newRow.classList.add("bg-green-100")
      setTimeout(() => newRow.classList.remove("bg-green-100"), 2500)
    } else {
      console.log("[Pyramid] 分数不变 (" + newScore + ")，仅更新时间戳")
      newRow.classList.add("bg-blue-50")
      setTimeout(() => newRow.classList.remove("bg-blue-50"), 1500)
    }

    const btn = newRow.querySelector("button[data-action=\"pyramid#recalculate\"]")
    if (btn) {
      setTimeout(() => {
        btn.disabled = false
        btn.textContent = "重新计算"
      }, 200)
    }

    this._autoHideStatus(stockId)
  }

  _autoHideStatus(stockId) {
    setTimeout(() => {
      const statusEl = document.getElementById("pyramid-status-" + stockId)
      if (statusEl) {
        statusEl.innerHTML = ""
      }
    }, 3500)
  }
}