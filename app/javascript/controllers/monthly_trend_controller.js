import { Controller } from "@hotwired/stimulus"

// 月K · MACD · 月ROE 三联图
// 三图共用一个 ECharts 实例、三个 grid，共用同一份月份数组（category 轴）；
// 上两图隐藏 x 轴刻度，由最下方 ROE 图给出月份标签。grid 几何由 ERB 占位元素实测得出（见 gridsFromLayout），
// 避免 JS 常量与模板高度漂移 —— 这是从「Chart.js + ECharts 混合渲染 + 人工约定轴宽」迁移过来的核心目的。
//
// ECharts 走 npmmirror CDN 懒加载（仅当三联图进入视口才注入脚本），不进入 esbuild 产物
const ECHARTS_VERSION = "6.1.0"
const ECHARTS_URL = `https://registry.npmmirror.com/echarts/${ECHARTS_VERSION}/files/dist/echarts.min.js`

// 右侧留白：仅需容纳 y 轴刻度标签（如 "2,000"、"39%"）。刻度文字实测约 30px，加 ECharts 默认 8px 轴间距
// 共约 38px，取 44px 已无多余空白。ECharts 的轴标签防溢出钳制已在 gridsFromLayout
// 显式关闭（outerBoundsMode: 'none'），故此值必须自己够宽，不能再指望框架帮忙兜底
const RIGHT_GUTTER = 44

// 左侧留白：0 —— 首月标签改用 axisLabel.alignMinLabel: 'left'（见 buildXAxis）贴住轴起点左对齐，
// 不再需要为「居中标签向左溢出半字宽」预留空间。绘图区左边界因此与卡片内容区左边界重合，
// 与卡片标题、caption 行落在同一条竖线上，消除「卡片内边距 + 轴留白」的双层内缩
const LEFT_GUTTER = 0

// 默认可视窗口：近 10 年（120 个月）。数据一次性取「全部历史」，本常量只决定初次渲染的窗口宽度
// 与「近10年」按钮的定位目标 —— 之后左右拖动都只是在本窗口里滑动回看，不再重复请求接口
const DEFAULT_WINDOW_MONTHS = 120

// 最小可视窗口（月）：与 dataZoom 的 minValueSpan 同一口径，避免自定义滚轮缩放越过内置下限后打架
const MIN_WINDOW_MONTHS = 6

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

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

export default class extends Controller {
  static targets = ["rangeBtn", "adjBtn", "chart", "overlay", "macdNote", "status", "charts"]
  static values = { url: String }

  connect() {
    // 交互模型：一次性取「全部历史」（buildUrl 里 range 恒为 all），之后在本地窗口里左右滑动回看。
    // activeRange 只表示「当前窗口落在哪个预设档位」，用于按钮高亮，不再参与请求参数
    this.activeRange = "10y"
    this.adj = "qfq"
    this.requestId = 0
    this.disposed = false
    this.chart = null
    this.echartsPromise = null
    this.resizeHandler = null
    this.zoomHandler = null
    // 滚轮/触控板手势监听（捕获阶段挂在画布容器上）与横向平移的亚像素余量
    this.wheelHandler = null
    this.panRemainder = 0
    // 重渲染（切换复权）后要恢复的窗口；null 表示回到默认「近10年」
    this.pendingWindow = null
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

  // 「近10年 / 全部」= 瞬时定位：数据早已全量在手，只把 dataZoom 窗口挪到位，不再发请求
  switchRange(event) {
    const value = event.currentTarget.dataset.range

    if (!this.chart) {
      // 数据或图库还没就绪：先记下目标，渲染完成后按它定位，避免这次点击石沉大海
      this.pendingWindow = value
      this.setActiveRange(value)
      return
    }

    this.applyWindow(value)
  }

  switchAdj(event) {
    const value = event.currentTarget.dataset.adj
    if (value === this.adj) return

    // 复权只改数值口径、不该改时间窗口：先记下当前位置，重画后原地恢复，
    // 否则用户刚拖到 2008 年、一切复权就被弹回默认窗口。
    // 图表尚未创建时 currentWindow() 返回 null（图库还在加载），此时不能拿 null 覆盖掉
    // switchRange 刚记下的档位，否则那次「全部」点击会被静默丢弃
    this.pendingWindow = this.currentWindow() || this.pendingWindow
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
      this.bindZoom()
      this.bindWheel()
    }

    // notMerge：切换区间/复权时整体替换，避免旧 series 残留
    this.chart.setOption(this.buildOption(labels, grids), { notMerge: true })

    // 整体替换会把 dataZoom 窗口重置为「全部」，故此处必须重新定位：
    // 切换复权时回到用户原位置，其余情况回到默认「近10年」
    this.applyWindow(this.pendingWindow || "10y")
    this.pendingWindow = null
  }

  // 窗口定位：target 为预设档位名（"10y" / "all"），或 { startValue, endValue }（复权重画后原地恢复）
  applyWindow(target) {
    const last = this.barData.length - 1
    if (!this.chart || last < 0) return

    // 变量名刻意避开 window：这里装的是 dataZoom 窗口，不是全局对象
    const zoomWindow =
      typeof target === "string"
        ? {
            startValue: target === "all" ? 0 : Math.max(0, last - (DEFAULT_WINDOW_MONTHS - 1)),
            endValue: last
          }
        : target

    // 不传 dataZoomIndex：实测 ECharts 会对所有 dataZoom 组件（inside + slider）同时生效
    this.chart.dispatchAction({ type: "dataZoom", ...zoomWindow })
    this.setActiveRange(this.windowRange(zoomWindow))
  }

  // 窗口落在哪个预设档位：**盖住全部历史**才算「全部」，否则一律归「近10年」。
  // 不能只看 startValue —— 上市不足 120 个月的新股点「近10年」时 startValue 本来就是 0，
  // 在最左端放大到只看早期若干年时 startValue 也是 0，两种都会误亮「全部」
  windowRange(zoomWindow) {
    return zoomWindow.startValue <= 0 && zoomWindow.endValue >= this.barData.length - 1 ? "all" : "10y"
  }

  // 读回当前窗口（复权切换前先存下来）。ECharts 会把 start/end（百分比）与 startValue/endValue（下标）
  // 两种口径同时写回 option，任取其一即可；这里优先用下标，缺失时再由百分比换算
  currentWindow() {
    const zoom = this.chart && (this.chart.getOption().dataZoom || [])[0]
    if (!zoom) return null

    const last = this.barData.length - 1
    const index = (value, percent, fallback) => {
      if (typeof value === "number") return value
      if (typeof percent === "number") return Math.round((percent / 100) * last)
      return fallback
    }

    return {
      startValue: index(zoom.startValue, zoom.start, 0),
      endValue: index(zoom.endValue, zoom.end, last)
    }
  }

  // 用户拖动/滚轮缩放后，让「近10年 / 全部」高亮跟随窗口实际范围：
  // 窗口盖住全部历史才算「全部」，其余（含滚轮缩放出的任意区间）都归到「近10年」
  bindZoom() {
    if (!this.chart || this.zoomHandler) return

    this.zoomHandler = () => {
      const zoomWindow = this.currentWindow()
      if (!zoomWindow) return

      this.setActiveRange(this.windowRange(zoomWindow))
    }
    this.chart.on("datazoom", this.zoomHandler)
  }

  // 滚轮 / 触控板双指手势。ECharts 的 inside dataZoom 会无条件吃掉画布上的滚轮事件：
  // v6.1.0 的 _mousewheelHandler 先经 _checkTriggerMoveZoom 调 preventDefault（只要指针落在
  // 组件矩形内就调，且 _opt 里的 zoomOnMouseWheel 被写成常量 true），之后才用 isAvailableBehavior
  // 判断 zoomOnMouseWheel / moveOnMouseWheel 是否允许触发 —— 也就是说把配置改成 false 也拦不住它
  // preventDefault，「鼠标停在图上时整页无法上下滚动」正是这么来的。
  // 故改为在捕获阶段接管：一律 stopPropagation 让 zrender 根本收不到滚轮，
  // 再按手势决定是否 preventDefault —— 纵向滚轮不调，浏览器照常滚动整页；
  // 只有横向手势（触控板双指平移）与 Shift+滚轮 / 触控板捏合由图表消费。
  bindWheel() {
    if (this.wheelHandler) return

    this.wheelHandler = (event) => {
      if (!this.chart) return

      event.stopPropagation()

      // Firefox 的滚轮以「行」为单位（deltaMode=1），换算成像素再参与计算，否则一次滚动挪不足 1 个月
      const unit = event.deltaMode === 1 ? 16 : 1
      const deltaX = event.deltaX * unit
      const deltaY = event.deltaY * unit

      // Shift+滚轮与触控板捏合都按缩放处理。捏合在 Chrome 里就是 wheel + ctrlKey，
      // 不接管的话会触发浏览器整页缩放（页面元素忽大忽小），这里 preventDefault 后交给图表
      if (event.shiftKey || event.ctrlKey) {
        event.preventDefault()
        this.zoomByWheel(event, deltaY || deltaX)
      } else if (Math.abs(deltaX) > Math.abs(deltaY)) {
        event.preventDefault()
        this.panByWheel(deltaX)
      }
    }
    this.chartTarget.addEventListener("wheel", this.wheelHandler, { passive: false, capture: true })
  }

  // Shift+滚轮缩放：以指针所在月份为锚点（该月份在屏幕上原地不动），窗口宽度按滚轮方向收放
  zoomByWheel(event, delta) {
    const current = this.currentWindow()
    const last = this.barData.length - 1
    if (!current || last < 0 || !delta) return

    const span = current.endValue - current.startValue + 1
    const nextSpan = clamp(Math.round(span * (delta < 0 ? 0.8 : 1.25)), MIN_WINDOW_MONTHS, last + 1)
    if (nextSpan === span) return

    const rect = this.chartTarget.getBoundingClientRect()
    const raw = this.chart.convertFromPixel({ xAxisIndex: 0 }, [event.clientX - rect.left, 0])
    const value = Array.isArray(raw) ? raw[0] : raw
    const anchor = Number.isFinite(value)
      ? clamp(value, current.startValue, current.endValue)
      : (current.startValue + current.endValue) / 2

    const ratio = span > 1 ? (anchor - current.startValue) / (span - 1) : 0
    const start = clamp(Math.round(anchor - ratio * (nextSpan - 1)), 0, last + 1 - nextSpan)

    this.applyWindow({ startValue: start, endValue: start + nextSpan - 1 })
  }

  // 触控板双指横向平移：像素 → 月份用当前窗口宽度换算，方向与 ECharts 按住拖动一致
  //（内容跟着手指走：双指右滑 = 内容右移 = 看到更早的月份）。
  // 亚像素余量累计后再取整：触控板慢速滑动单次位移常常不足 1 个月，直接取整会被整段吃掉
  panByWheel(deltaX) {
    const current = this.currentWindow()
    const last = this.barData.length - 1
    const width = this.chart.getWidth() - LEFT_GUTTER - RIGHT_GUTTER
    if (!current || last < 0 || width <= 0) return

    const span = current.endValue - current.startValue + 1
    this.panRemainder += deltaX * (span / width)

    const shift = Math.trunc(this.panRemainder)
    if (!shift) return

    this.panRemainder -= shift
    // 顶到两端时保持窗口宽度不变，只把窗口贴在边界上（clamp 后与原位置相同则不再派发）
    const start = clamp(current.startValue + shift, 0, Math.max(0, last + 1 - span))
    if (start === current.startValue) return

    this.applyWindow({ startValue: start, endValue: start + span - 1 })
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

    // 容器为给 K 线顶部刻度留出可绘制空间而设了 padding-top，而画布是 absolute inset-0 ——
    // 它铺满容器的 padding box（这段内边距也包括在内），overlay 却被这段内边距在文档流里整体下推。
    // grid 的坐标原点在画布左上角，故三个 grid 的 top 都要补上这段差值，否则三格会整体高出 caption 行
    const topInset = Math.round(
      this.overlayTarget.getBoundingClientRect().top - this.chartTarget.getBoundingClientRect().top
    )

    return ["kline", "macd", "roe"].map((name) => ({
      // 关闭 ECharts 6 的轴标签防溢出钳制（默认 'auto'）：它按采样标签估算，会单独收缩某一个 grid，
      // 使三个 grid 的矩形不等、十字准星越往左错位越大。设为 'none' 后 rect 完全由下面的常量与模板高度决定，
      // 三个 grid 恒等 —— 这是比「靠留白让机制不触发」更稳的根治手段
      outerBoundsMode: "none",
      left: LEFT_GUTTER,
      right: RIGHT_GUTTER,
      top: topInset + bands[name].top,
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

      // scale 口径对齐原 Chart.js：K/MACD 贴合数据区间（MACD 由 scale:false 强制含 0，柱状图基线）；
      // ROE 显式指定轴底（见 roeFloor）：正常以 0% 为底，收益率高度才能跨区间横向比较，不受当期最低点抬升
      yAxis: [
        this.buildYAxis(0, true),
        this.buildYAxis(1, false),
        this.buildYAxis(2, false, "%", this.roeFloor())
      ],

      // 跨三图联动十字准星（官方只承诺指示线同步；tooltip 内容由 buildTooltip 自拼）
      axisPointer: {
        link: [{ xAxisIndex: "all" }],
        label: { show: false }
      },

      dataZoom: [
        // 滚轮与触控板手势由 bindWheel 在 DOM 捕获阶段接管（原因见该方法注释：ECharts 6.1.0 的
        // inside 无论如何都会 preventDefault 掉滚轮，配置成 false 也拦不住），
        // 这里显式关掉两个滚轮开关，只保留按住拖动平移与触屏双指捏合缩放
        {
          type: "inside",
          xAxisIndex: [0, 1, 2],
          zoomOnMouseWheel: false,
          moveOnMouseMove: true,
          moveOnMouseWheel: false,
          minValueSpan: MIN_WINDOW_MONTHS
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
          minValueSpan: MIN_WINDOW_MONTHS
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
        ? {
            fontSize: 10,
            color: TICK_COLOR,
            maxRotation: 0,
            hideOverlap: true,
            // 首月标签默认以刻度为居中，会向左溢出约半字宽（"2016-10" 约 19px）；
            // grid.left 已压到 0，故把最左侧标签改为左对齐贴住轴起点，避免被画布裁切
            alignMinLabel: "left"
          }
        : { show: false }
    }
  }

  buildYAxis(gridIndex, scale, unit = "", min = null) {
    const axis = {
      gridIndex,
      scale,
      position: "right",
      splitNumber: 4, // 约 5 条刻度，对齐原 maxTicksLimit: 5
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { fontSize: 10, color: TICK_COLOR, formatter: `{value}${unit}` },
      splitLine: { lineStyle: { color: SPLIT_LINE_COLOR } }
    }

    // 显式给定轴底就用它（ROE 的 0% 基准）；否则交由 ECharts 自动取整
    if (min !== null) axis.min = min

    return axis
  }

  // ROE 轴底：正常为 0%；历史出现过亏损（ROE < 0）时下探到最低值，避免曲线被轴底截断；无数据则退化为 0
  roeFloor() {
    const values = this.roeData
      .map((item) => (item && item.value !== null && item.value !== undefined ? Number(item.value) : NaN))
      .filter((value) => Number.isFinite(value))

    return values.length ? Math.min(0, ...values) : 0
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
    // 滚轮监听挂在画布容器上（非 window），但容器会被 Turbo 整页替换，同样要显式摘下
    if (this.wheelHandler) {
      this.chartTarget.removeEventListener("wheel", this.wheelHandler, { capture: true })
      this.wheelHandler = null
    }
    // ECharts 实例只有 dispose()，没有 Chart.js 的 destroy()；dispose 会一并摘掉 datazoom 监听
    if (this.chart) {
      this.chart.dispose()
      this.chart = null
    }
    this.zoomHandler = null
    this.chartTarget.innerHTML = ""
  }

  fmt(value) {
    if (value === null || value === undefined) return "-"
    return Number(value).toFixed(2)
  }

  buildUrl() {
    const url = new URL(this.urlValue, window.location.origin)
    // 区间恒为 all：一次把全部历史取回本地，之后左右拖动即在本窗口内滑动回看更早的月K，
    // 拖到最左即可一路退到上市初期（与财务表格「初始停在最新、向左滑看历史」同一套心智）
    url.searchParams.set("range", "all")
    url.searchParams.set("adj", this.adj)
    return url.toString()
  }

  setActiveRange(value) {
    if (value === this.activeRange) return

    this.activeRange = value
    this.syncButtons()
  }

  syncButtons() {
    this.rangeBtnTargets.forEach((btn) => this.applyActive(btn, btn.dataset.range === this.activeRange))
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