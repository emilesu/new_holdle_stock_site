import { Controller } from "@hotwired/stimulus"

// 月K · MACD · 月ROE 三联图
// 三图共用同一份月份数组（category 轴），上两图隐藏 x 轴刻度，由最下方 ROE 图给出月份标签
const Y_AXIS_WIDTH = 64

export default class extends Controller {
  static targets = ["rangeBtn", "adjBtn", "kline", "macd", "roe", "macdNote", "status", "charts"]
  static values = { url: String }

  connect() {
    this.range = "10y"
    this.adj = "qfq"
    this.charts = {}
    this.requestId = 0
    this.skipRoe = false
    this.disposed = false

    this.syncButtons()
    this.setStatus("加载中…")

    // 懒加载：图表进入视口才请求，避免拖慢详情页首屏
    this.observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return
      this.observer.disconnect()
      this.observer = null
      this.load()
    }, { rootMargin: "120px" })
    this.observer.observe(this.element)
  }

  // Turbo 整页替换会触发 disconnect：必须销毁图表与 observer，防止 canvas 残留与内存泄漏
  disconnect() {
    this.disposed = true
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
    this.destroyCharts()
  }

  switchRange(event) {
    const value = event.currentTarget.dataset.range
    if (value === this.range) return

    this.range = value
    this.syncButtons()
    this.load()
  }

  switchAdj(event) {
    const value = event.currentTarget.dataset.adj
    if (value === this.adj) return

    this.adj = value
    // ROE 是比率，与复权口径无关：仅切复权时不重绘 ROE 图
    this.skipRoe = true
    this.syncButtons()
    this.load()
  }

  async load() {
    const requestId = ++this.requestId
    // 已有图表时保留旧图，避免切换区间/复权时卡片闪现空白
    if (!this.charts.kline) this.setStatus("加载中…")

    try {
      const response = await fetch(this.buildUrl(), { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      // 旧请求返回时页面可能已被替换，丢弃过期响应
      if (this.disposed || requestId !== this.requestId) return

      this.render(payload)
    } catch (error) {
      if (this.disposed || requestId !== this.requestId) return

      console.error("monthly trend load error:", error)
      this.destroyCharts()
      this.setStatus("数据加载失败，请稍后重试")
    }
  }

  render(payload) {
    const bars = payload.bars || []
    if (!bars.length) {
      this.destroyCharts()
      this.setStatus("暂无数据")
      return
    }

    this.barData = bars
    const labels = bars.map((bar) => String(bar.t || "").slice(0, 7))

    this.setStatus("")
    this.renderKline(labels, bars)
    this.renderMacd(labels, payload.macd || [], payload.adj)
    if (!(this.skipRoe && this.charts.roe)) this.renderRoe(labels, payload.roe || [])
    this.skipRoe = false
  }

  renderKline(labels, bars) {
    if (this.charts.kline) this.charts.kline.destroy()

    this.charts.kline = new Chart(this.klineTarget, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "收盘",
          data: bars.map((bar) => bar.c),
          borderColor: "rgb(239, 68, 68)",
          backgroundColor: "rgba(239, 68, 68, 0.08)",
          borderWidth: 1.5,
          pointRadius: 0,
          pointHoverRadius: 3,
          fill: false,
          tension: 0
        }]
      },
      options: this.baseOptions({ tooltipLabel: (context) => this.ohlcLines(context.dataIndex) })
    })
  }

  renderMacd(labels, macd, adj) {
    if (this.charts.macd) this.charts.macd.destroy()

    const hist = macd.map((item) => item.hist)

    this.charts.macd = new Chart(this.macdTarget, {
      type: "bar",
      data: {
        labels,
        datasets: [
          {
            type: "bar",
            label: "HIST",
            data: hist,
            backgroundColor: hist.map((value) => (value >= 0 ? "rgba(239, 68, 68, 0.55)" : "rgba(16, 185, 129, 0.55)")),
            borderWidth: 0,
            barPercentage: 0.9,
            order: 1
          },
          {
            type: "line",
            label: "DIF",
            data: macd.map((item) => item.dif),
            borderColor: "rgb(239, 68, 68)",
            borderWidth: 1.2,
            pointRadius: 0,
            tension: 0,
            order: 2
          },
          {
            type: "line",
            label: "DEA",
            data: macd.map((item) => item.dea),
            borderColor: "rgb(59, 130, 246)",
            borderWidth: 1.2,
            pointRadius: 0,
            tension: 0,
            order: 2
          }
        ]
      },
      options: this.baseOptions({
        tooltipLabel: (context) => `${context.dataset.label} ${this.fmt(context.parsed.y)}`
      })
    })

    if (this.hasMacdNoteTarget) {
      this.macdNoteTarget.textContent = `MACD · ${adj === "hfq" ? "后复权" : "前复权"}口径`
    }
  }

  renderRoe(labels, roe) {
    if (this.charts.roe) this.charts.roe.destroy()

    this.charts.roe = new Chart(this.roeTarget, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "ROE",
          data: roe.map((item) => item.value),
          borderColor: "rgb(245, 158, 11)",
          backgroundColor: "rgba(245, 158, 11, 0.08)",
          borderWidth: 1.5,
          pointRadius: 0,
          fill: false,
          stepped: true,
          // 无年报覆盖的月份留空断线，不画 0
          spanGaps: false
        }]
      },
      options: this.baseOptions({
        showXTicks: true,
        yUnit: "%",
        tooltipLabel: (context) => {
          const item = roe[context.dataIndex]
          const report = item && item.report_date ? `（年报 ${item.report_date}）` : ""
          return `ROE ${this.fmt(context.parsed.y)}%${report}`
        }
      })
    })
  }

  // 三图共用配置：固定 y 轴宽度，保证上下三图的月份严格对齐
  baseOptions({ showXTicks = false, yUnit = "", tooltipLabel = null } = {}) {
    const callbacks = tooltipLabel ? { label: tooltipLabel } : {}

    return {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: { displayColors: false, callbacks }
      },
      scales: {
        x: {
          type: "category",
          ticks: {
            display: showXTicks,
            maxRotation: 0,
            autoSkip: true,
            maxTicksLimit: 12,
            font: { size: 10 },
            color: "#9ca3af"
          },
          grid: { display: false },
          border: { color: "rgba(0, 0, 0, 0.1)" }
        },
        y: {
          position: "right",
          afterFit: (scale) => { scale.width = Y_AXIS_WIDTH },
          ticks: {
            maxTicksLimit: 5,
            font: { size: 10 },
            color: "#9ca3af",
            callback: (value) => `${value}${yUnit}`
          },
          grid: { color: "rgba(0, 0, 0, 0.06)" },
          border: { display: false }
        }
      }
    }
  }

  ohlcLines(index) {
    const bar = this.barData && this.barData[index]
    if (!bar) return ""

    return [
      `开 ${this.fmt(bar.o)}`,
      `高 ${this.fmt(bar.h)}`,
      `低 ${this.fmt(bar.l)}`,
      `收 ${this.fmt(bar.c)}`
    ]
  }

  fmt(value) {
    if (value === null || value === undefined) return "-"
    return Number(value).toFixed(2)
  }

  buildUrl() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("range", this.range)
    url.searchParams.set("adj", this.adj)
    return url.toString()
  }

  syncButtons() {
    this.rangeBtnTargets.forEach((btn) => this.applyActive(btn, btn.dataset.range === this.range))
    this.adjBtnTargets.forEach((btn) => this.applyActive(btn, btn.dataset.adj === this.adj))
  }

  applyActive(btn, active) {
    btn.classList.toggle("text-ink", active)
    btn.classList.toggle("text-muted-4", !active)
    btn.setAttribute("aria-pressed", active ? "true" : "false")
  }

  setStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.classList.toggle("hidden", !message)
    }
    if (this.hasChartsTarget) this.chartsTarget.classList.toggle("hidden", Boolean(message))
  }

  destroyCharts() {
    Object.values(this.charts).forEach((chart) => chart && chart.destroy())
    this.charts = {}
  }
}