import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["market", "sector"]

  connect() {
    this.sectorCache = {}
  }

  async changeMarket() {
    const market = this.marketTarget.value
    const sectorSelect = this.sectorTarget

    if (this.sectorCache[market]) {
      this.updateSectorOptions(sectorSelect, this.sectorCache[market])
      return
    }

    sectorSelect.disabled = true
    sectorSelect.innerHTML = '<option value="">加载中...</option>'

    try {
      const response = await fetch(`/admin/stocks/sectors?market=${market}`)
      const sectors = await response.json()
      this.sectorCache[market] = sectors
      this.updateSectorOptions(sectorSelect, sectors)
    } catch (error) {
      console.error("加载行业列表失败:", error)
      this.updateSectorOptions(sectorSelect, [])
    } finally {
      sectorSelect.disabled = false
    }
  }

  updateSectorOptions(select, sectors) {
    const currentValue = select.dataset.currentSector || ""
    let html = '<option value="">全部</option>'
    sectors.forEach(s => {
      const selected = s === currentValue ? "selected" : ""
      html += `<option value="${s}" ${selected}>${s}</option>`
    })
    select.innerHTML = html
  }
}