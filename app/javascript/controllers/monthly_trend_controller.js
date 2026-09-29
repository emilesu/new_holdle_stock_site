import { Controller } from "@hotwired/stimulus"

// 月K · MACD · 月ROE 三联图
// 三图共用一个 ECharts 实例、三个 grid，共用同一份月份数组（category 轴）；
// 上两图隐藏 x 轴刻度，由最下方 ROE 图给出月份标签。grid 几何由 ERB 占位元素实测得出（见 gridsFromLayout），
// 避免 JS 常量与模板高度漂移 —— 这是从「Chart.js + ECharts 混合渲染 + 人工约定轴宽」迁移过来的核心目的。
//
// ECharts 走 npmmirror CDN 懒加载（仅当三联图进入视口才注入脚本），不进入 esbuild 产物
const ECHARTS_VERSION = "6.1.0"
const ECHARTS_URL = `https://registry.npmmirror.com/echarts/${ECHARTS_VERSION}/files/dist/echarts.min.js`

// 右侧留白：容纳 y 轴刻度标签（如 "2,500"、"12.34%"）。ECharts 的轴标签防溢出钳制已在 gridsFromLayout
// 显式关闭（outerBoundsMode: 'none'），故此值必须自己够宽，不能再指望框架帮忙兜底
const RIGHT_GUTTER = 72

// 左侧留白：category 轴的首个月份标签以「半字宽」为居中半径（实测约 23px），grid.left 小于该值时标签会
// 越出画布左边缘被裁切。28px 使首月标签天然落在画布内 —— 这里只是单纯给标签留位置，
// 不再承担「规避 ECharts 防溢出收缩」的职责（那件事已由外层的 outerBoundsMode: 'none' 根治）
const LEFT_GUTTER = 28

// 站内 A股配色：红涨绿跌
const UP_COLOR = "#ef4444"
const DOWN_COLOR = "#10b981"
const HIST_UP_COLOR = "rgba(239, 68, 68, 0.55)"
const HIST_DOWN_COLOR = "rgba(16, 185, 129, 0.55)"
const DIF_COLOR = "#ef4444"
const DEA_COLOR = "#3b82f6"
const ROE_COLOR = "#f59e0b"
const TICK_COLOR = "#9ca3af"
const SPLIT_LINE_COLOR = "rgba(0, 0, 0, 0.06)"
const AXIS_LINE_COLOR = "rgba(0, 0, 0, 0.1)"

export default class extends Controller {
  static targets = ["rangeBtn", "adjBtn", "chart", "overlay", "macdNote", "status", "charts"]
  static values = { url: String }

  connect() {
    this.range = "10y"
    this.adj = "qfq"
    this.requestId = 0
    this.disposed = false
    this.chart = null
    this.echartsPromise = null
    this.resizeHandler = null
    this.barData = []
    this.macdData = []
    this.roeData = []

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
    // 页面被整页替换时必须摘掉 window 监听，否则会随访问次数累积
    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler)
      this.resizeHandler = null
    }
    this.disposeChart()
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
    this.syncButtons()
    this.load()
  }

  async load() {
    const requestId = ++this.requestId
    // 已有图表时保留旧图，避免切换区间/复权时卡片闪现空白
    if (!this.chart) this.setStatus("加载中…")

    try {
      const response = await fetch(this.buildUrl(), { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      // 旧请求返回时页面可能已被替换，丢弃过期响应
      if (this.disposed || requestId !== this.requestId) return

      // 必须 await：renderChart 是异步的，浮空调用会让它的异常逃出本方法的 try/catch
      await this.render(payload)
    } catch (error) {
      if (this.disposed || requestId !== this.requestId) return

      console.error("monthly trend load error:", error)
      this.disposeChart()
      this.setStatus("数据加载失败，请稍后重试")
    }
  }

  render(payload) {
    const bars = payload.bars || []
    if (!bars.length) {
      this.disposeChart()
      this.setStatus("暂无数据")
      return
    }

    this.barData = bars
    this.macdData = payload.macd || []
    this.roeData = payload.roe || []

    // 顺序不可颠倒：charts 容器此前是 hidden（尺寸 0），必须先取消隐藏再 init，否则得到 0×0 空白图
    this.setStatus("")

    if (this.hasMacdNoteTarget) {
      this.macdNoteTarget.textContent = `MACD · ${payload.adj === "hfq" ? "后复权" : "前复权"}口径`
    }

    // 返回 promise：由 load() await，异常才能被它的 try/catch 兜住
    return this.renderChart(bars.map((bar) => String(bar.t || "").slice(0, 7)))
  }

  // 单实例渲染：三 grid + 5 个 series 一次 setOption
  async renderChart(labels) {
    const generation = this.requestId

    // 几何测量与 overlay 内边距回写都放在 await 之前：render() 已 setStatus("") 使容器可见，此刻即可测量；
    // 不必等 1.1MB 的 ECharts 脚本下完，caption 行在等待期间就已完成对齐，
    // 且后续 ensureECharts 加载失败的降级态也同样带着正确的内边距
    const grids = this.gridsFromLayout()
    if (!grids) {
      // 此时 render() 已 setStatus("") 把容器显示出来了，必须补一句提示，否则用户只看到空白卡片
      this.setStatus("图表布局异常，请刷新重试")
      return
    }

    // caption 行（MACD 标题行等）随 overlay 左右内边距一起内缩，使其左右端点正好落在绘图区左右边界上，
    // 而不是顶到卡片边缘（右侧 72px 是 y 轴标签的位置，caption 顶到那里会横跨整张卡片）；
    // 内缩值直接取自上面算出的 grid 边界，常量只在 JS 侧维护一份，避免 ERB 再写一套导致漂移
    this.overlayTarget.style.paddingLeft = `${grids[0].left}px`
    this.overlayTarget.style.paddingRight = `${grids[0].right}px`

    let echarts
    try {
      echarts = await this.ensureECharts()
    } catch (error) {
      console.error("echarts load error:", error)
      if (this.disposed || generation !== this.requestId) return

      this.disposeChart()
      this.chartTarget.innerHTML =
        '<div class="h-full flex items-center justify-center text-hl-12 text-muted-4">图表库加载失败</div>'
      return
    }

    // 等待脚本期间若已发起新请求或页面已被替换，丢弃本次渲染
    if (this.disposed || generation !== this.requestId) return

    if (!this.chart) {
      this.chartTarget.innerHTML = ""
      this.chart = echarts.init(this.chartTarget)
      this.bindResize()
    }

    // notMerge：切换区间/复权时整体替换，避免旧 series 残留
    this.chart.setOption(this.buildOption(labels, grids), { notMerge: true })
  }

  // grid 矩形：top/height 的唯一真源是 ERB 占位元素（改模板高度类图表自动跟随，避免 JS 常量漂移）；
  // left/right 只能来自 JS 常量 —— 它取决于 y 轴刻度标签宽度，ERB 里无法表达，
  // 故改用「把同一组常量回写成 overlay 内边距」的方式让 caption 行与绘图区对齐（见 renderChart）
  gridsFromLayout() {
    const bands = {}
    this.overlayTarget.querySelectorAll("[data-band]").forEach((el) => {
      bands[el.dataset.band] = { top: el.offsetTop, height: el.offsetHeight }
    })

    if (!bands.kline || !bands.macd || !bands.roe) {
      console.error("monthly trend: grid 占位元素缺失", bands)
      return null
    }

    return ["kline", "macd", "roe"].map((name) => ({
      // 关闭 ECharts 6 的轴标签防溢出钳制（默认 'auto'）：它按采样标签估算，会单独收缩某一个 grid，
      // 使三个 grid 的矩形不等、十字准星越往左错位越大。设为 'none' 后 rect 完全由下面的常量与模板高度决定，
      // 三个 grid 恒等 —— 这是比「靠留白让机制不触发」更稳的根治手段
      outerBoundsMode: "none",
      left: LEFT_GUTTER,
      right: RIGHT_GUTTER,
      top: bands[name].top,
      height: bands[name].height
    }))
  }

  buildOption(labels, grids) {
    const bars = this.barData
    const macd = this.macdData
    const roe = this.roeData

    return {
      animation: false,
      // 全局字体必须放在这一份 option 里：另起一次 setOption 设 textStyle 会被下面 notMerge 的整体替换冲掉
      textStyle: { fontFamily: this.chartFontFamily() },

      // 三个 grid 共用同一组 left/right → 像素级对齐；不使用 containLabel（v6 已 deprecated 且会破坏对齐）
      grid: grids,

      xAxis: [
        this.buildXAxis(0, labels, false),
        this.buildXAxis(1, labels, false),
        this.buildXAxis(2, labels, true)
      ],

      // scale 口径对齐原 Chart.js：K/ROE 贴合数据区间；MACD 强制含 0（柱状图基线）
      yAxis: [
        this.buildYAxis(0, true),
        this.buildYAxis(1, false),
        this.buildYAxis(2, true, "%")
      ],

      // 跨三图联动十字准星（官方只承诺指示线同步；tooltip 内容由 buildTooltip 自拼）
      axisPointer: {
        link: [{ xAxisIndex: "all" }],
        label: { show: false }
      },

      dataZoom: [
        // 触屏：单指不拦截页面滚动，双指缩放；PC：Shift+滚轮缩放（普通滚轮仍滚动页面），按住拖动平移
        {
          type: "inside",
          xAxisIndex: [0, 1, 2],
          zoomOnMouseWheel: "shift",
          moveOnMouseMove: true,
          moveOnMouseWheel: false,
          minValueSpan: 6
        },
        // 拖拽条：所有设备可用的兜底缩放方式；占用底部 20px
        {
          type: "slider",
          xAxisIndex: [0, 1, 2],
          bottom: 6,
          height: 20,
          brushSelect: false,
          showDetail: false,
          borderColor: AXIS_LINE_COLOR,
          fillerColor: "rgba(0, 0, 0, 0.04)",
          handleStyle: { color: "#d1d5db", borderColor: "#d1d5db" },
          moveHandleStyle: { color: "#d1d5db" },
          textStyle: { color: TICK_COLOR, fontSize: 10 },
          minValueSpan: 6
        }
      ],

      tooltip: {
        trigger: "axis",
        axisPointer: { type: "cross", snap: true, label: { show: false } },
        // 卡片是 overflow-hidden，不挂 body 会被裁切
        appendToBody: true,
        backgroundColor: "rgba(17, 24, 39, 0.92)",
        borderWidth: 0,
        padding: [6, 8],
        textStyle: { color: "#f9fafb", fontSize: 11 },
        formatter: (params) => {
          const item = Array.isArray(params) ? params[0] : params
          return this.buildTooltip(item && item.dataIndex)
        }
      },

      series: [
        {
          name: "月K",
          type: "candlestick",
          xAxisIndex: 0,
          yAxisIndex: 0,
          // ECharts candlestick 数据顺序固定为 [开, 收, 低, 高]，由后端下发的 o/h/l/c 重排
          data: bars.map((bar) => [bar.o, bar.c, bar.l, bar.h]),
          barMaxWidth: 10,
          itemStyle: {
            color: UP_COLOR,
            color0: DOWN_COLOR,
            borderColor: UP_COLOR,
            borderColor0: DOWN_COLOR
          }
        },
        {
          name: "HIST",
          type: "bar",
          xAxisIndex: 1,
          yAxisIndex: 1,
          data: macd.map((item) => item.hist),
          itemStyle: {
            color: (params) => (params.value >= 0 ? HIST_UP_COLOR : HIST_DOWN_COLOR)
          }
        },
        {
          name: "DIF",
          type: "line",
          xAxisIndex: 1,
          yAxisIndex: 1,
          data: macd.map((item) => item.dif),
          showSymbol: false,
          lineStyle: { width: 1.2, color: DIF_COLOR },
          itemStyle: { color: DIF_COLOR }
        },
        {
          name: "DEA",
          type: "line",
          xAxisIndex: 1,
          yAxisIndex: 1,
          data: macd.map((item) => item.dea),
          showSymbol: false,
          lineStyle: { width: 1.2, color: DEA_COLOR },
          itemStyle: { color: DEA_COLOR }
        },
        {
          name: "ROE",
          type: "line",
          xAxisIndex: 2,
          yAxisIndex: 2,
          data: roe.map((item) => item.value),
          showSymbol: false,
          // 阶梯方向与后端「生效月」语义一致：当月起向后延伸
          step: "end",
          // 无年报覆盖的月份是 null，默认不连接 → 自动断线，不画 0
          connectNulls: false,
          lineStyle: { width: 1.5, color: ROE_COLOR },
          itemStyle: { color: ROE_COLOR }
        }
      ]
    }
  }

  buildXAxis(gridIndex, labels, showLabel) {
    return {
      gridIndex,
      type: "category",
      data: labels,
      boundaryGap: true,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: AXIS_LINE_COLOR } },
      splitLine: { show: false },
      axisLabel: showLabel
        ? { fontSize: 10, color: TICK_COLOR, maxRotation: 0, hideOverlap: true }
        : { show: false }
    }
  }

  buildYAxis(gridIndex, scale, unit = "") {
    return {
      gridIndex,
      scale,
      position: "right",
      splitNumber: 4, // 约 5 条刻度，对齐原 maxTicksLimit: 5
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { fontSize: 10, color: TICK_COLOR, formatter: `{value}${unit}` },
      splitLine: { lineStyle: { color: SPLIT_LINE_COLOR } }
    }
  }

  // 三段自拼（价 / 量指标 / 基本面）：ECharts 只保证指示线跨 grid 联动，不合并 tooltip 内容，
  // 因此统一按同一个 dataIndex 从三份本地数据取值（后端三数组等长对齐）
  buildTooltip(index) {
    const bar = this.barData[index]
    if (!bar) return ""

    const lines = [
      String(bar.t || "").slice(0, 7),
      `开 ${this.fmt(bar.o)}　高 ${this.fmt(bar.h)}　低 ${this.fmt(bar.l)}　收 ${this.fmt(bar.c)}`
    ]

    const macd = this.macdData[index]
    if (macd) {
      lines.push(`MACD　HIST ${this.fmt(macd.hist)}　DIF ${this.fmt(macd.dif)}　DEA ${this.fmt(macd.dea)}`)
    }

    const roe = this.roeData[index]
    if (roe) {
      const value = roe.value === null || roe.value === undefined ? "-" : `${this.fmt(roe.value)}%`
      const report = roe.report_date ? `（年报 ${roe.report_date}）` : ""
      lines.push(`ROE ${value}${report}`)
    }

    return lines.join("<br/>")
  }

  // ECharts 脚本懒加载：三联图进入视口后才注入，其他页面零成本
  ensureECharts() {
    if (window.echarts) return Promise.resolve(window.echarts)
    if (this.echartsPromise) return this.echartsPromise

    this.echartsPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = ECHARTS_URL
      script.async = true
      script.onload = () => {
        if (window.echarts) resolve(window.echarts)
        else reject(new Error("echarts 加载完成但未挂到 window"))
      }
      script.onerror = () => reject(new Error(`echarts 脚本加载失败：${ECHARTS_URL}`))
      document.head.appendChild(script)
    }).catch((error) => {
      // 不缓存失败的 promise，后续切换区间时仍可重试
      this.echartsPromise = null
      throw error
    })

    return this.echartsPromise
  }

  // 让 canvas 文字与 Tailwind caption 同字体（--font-sans）
  chartFontFamily() {
    return window.getComputedStyle(this.chartTarget).fontFamily || "sans-serif"
  }

  // ECharts 不随容器自动缩放，需手动 resize
  bindResize() {
    if (this.resizeHandler) return

    this.resizeHandler = () => {
      if (this.chart) this.chart.resize()
    }
    window.addEventListener("resize", this.resizeHandler)
  }

  disposeChart() {
    // ECharts 实例只有 dispose()，没有 Chart.js 的 destroy()
    if (this.chart) {
      this.chart.dispose()
      this.chart = null
    }
    this.chartTarget.innerHTML = ""
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
}