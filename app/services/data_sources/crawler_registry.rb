module DataSources
  # 爬虫任务注册表 —— 全站唯一的任务定义源
  #
  # 后台按钮、路由、定时调度、失败重试全部由本表派生，不再散落硬编码。
  # 用 Ruby 常量而不是数据库表：任务与代码强绑定（类名、方法签名、kwargs），
  # 改代码必然要改任务定义，落 DB 只会引入「代码改了 DB 没改」的不一致；
  # 顺带收窄后台可执行面 —— 后台只接受注册表 key，不再接受任意类名字符串。
  module CrawlerRegistry
    # market: 该任务默认覆盖的市场（无市场概念的填 nil）
    # sync_data_type: 任务产出的数据类型，对应 StockDataSyncState::DATA_TYPES
    # accepts_stock_scope: 是否支持按股票子集执行（决定后台「批量补抓 / 失败重试」能否作用于它）
    # heavy: 重任务，后台会标注「建议低峰执行」
    Task = Struct.new(
      :key, :name, :group, :market, :service, :method_name, :kwargs,
      :sync_data_type, :accepts_stock_scope, :heavy, :description,
      keyword_init: true
    ) do
      def service_class
        service.to_s.constantize
      end

      def heavy?
        heavy == true
      end

      def accepts_stock_scope?
        accepts_stock_scope == true
      end
    end

    GROUPS = {
      "US" => "美股爬虫区",
      "HK" => "港股爬虫区",
      "CN" => "A股爬虫区",
      "BASE" => "基础数据",
      "CALC" => "数据计算",
      "QUALITY" => "数据质量"
    }.freeze

    TASKS = [
      # ── 美股 ──
      Task.new(
        key: "us_stock_list", name: "爬取美股列表", group: "US", market: "US",
        service: "DataSources::NasdaqStockListService", method_name: "call",
        sync_data_type: "profile", accepts_stock_scope: false, heavy: false,
        description: "从 NASDAQ API 拉取美股全量列表，新增/更新 stocks 记录"
      ),
      Task.new(
        key: "us_stock_basic", name: "爬取美股名称&行业", group: "US", market: "US",
        service: "DataSources::UsStockBasicInfoService", method_name: "call",
        sync_data_type: "profile", accepts_stock_scope: false, heavy: false,
        description: "补全美股名称、行业、交易所等基础信息"
      ),
      Task.new(
        key: "us_finance", name: "爬取美股全套财务", group: "US", market: "US",
        service: "DataSources::EastMoneyFinanceService", method_name: "call",
        kwargs: { market: "US" }, sync_data_type: "financial", accepts_stock_scope: true, heavy: true,
        description: "东方财富数据源，抓取利润表/资产负债表/现金流量表/财务指标四张报表"
      ),

      # ── 港股 ──
      Task.new(
        key: "hk_stock_list", name: "爬取港股列表、名称&行业", group: "HK", market: "HK",
        service: "DataSources::HkStockListService", method_name: "call",
        sync_data_type: "profile", accepts_stock_scope: false, heavy: false,
        description: "麦蕊智数拉列表 + 东方财富补行业分类与上市日期"
      ),
      Task.new(
        key: "hk_finance", name: "爬取港股全套财务", group: "HK", market: "HK",
        service: "DataSources::EastMoneyFinanceService", method_name: "call",
        kwargs: { market: "HK" }, sync_data_type: "financial", accepts_stock_scope: true, heavy: true,
        description: "东方财富数据源，抓取四张财务报表"
      ),

      # ── A股 ──
      Task.new(
        key: "a_stock_list", name: "爬取A股列表、名称&行业", group: "CN", market: "CN",
        service: "DataSources::AStockListService", method_name: "call",
        sync_data_type: "profile", accepts_stock_scope: false, heavy: false,
        description: "东方财富拉取 A 股列表，含行业板块与上市日期"
      ),
      Task.new(
        key: "a_finance", name: "爬取A股全套财务", group: "CN", market: "CN",
        service: "DataSources::EastMoneyFinanceService", method_name: "call",
        kwargs: { market: "CN" }, sync_data_type: "financial", accepts_stock_scope: true, heavy: true,
        description: "东方财富数据源，抓取四张财务报表"
      ),
      Task.new(
        key: "monthly_bars_fetch_cn", name: "A股月K全量重建", group: "CN", market: "CN",
        service: "DataSources::MonthlyBarBatchService", method_name: "call",
        kwargs: { mode: :full }, sync_data_type: "monthly_bar", accepts_stock_scope: true, heavy: true,
        description: "新浪月K + 复权因子全量重算并覆盖所有列，前复权基准变更时使用"
      ),
      Task.new(
        key: "monthly_bars_refresh_cn", name: "A股月K增量", group: "CN", market: "CN",
        service: "DataSources::MonthlyBarBatchService", method_name: "call",
        kwargs: { mode: :incremental }, sync_data_type: "monthly_bar", accepts_stock_scope: true, heavy: false,
        description: "已有历史行只重写前复权列，后复权列只增不改"
      ),

      # ── 基础数据 ──
      Task.new(
        key: "listing_date", name: "同步上市日期", group: "BASE", market: nil,
        service: "DataSources::StockListingDateService", method_name: "call",
        sync_data_type: "listing_date", accepts_stock_scope: true, heavy: false,
        description: "东方财富 F10 组织资料，补齐 listing_date 为空的股票（美股无此字段）"
      ),

      # ── 数据计算 ──
      Task.new(
        key: "update_all_pyramid", name: "全局更新金字塔分数", group: "CALC", market: nil,
        service: "DataSources::StockPyramidBatchService", method_name: "call",
        kwargs: { full_recalc: true }, accepts_stock_scope: false, heavy: true,
        description: "重算全站金字塔分数，耗时较长，建议低峰执行"
      ),
      Task.new(
        key: "refresh_all_radar", name: "雷达缓存(增量)", group: "CALC", market: nil,
        service: "DataSources::StockRadarBatchService", method_name: "call",
        kwargs: { full_recalc: false }, accepts_stock_scope: false, heavy: false,
        description: "增量刷新雷达维度缓存"
      ),
      Task.new(
        key: "refresh_all_radar_full", name: "雷达缓存(全量)", group: "CALC", market: nil,
        service: "DataSources::StockRadarBatchService", method_name: "call",
        kwargs: { full_recalc: true }, accepts_stock_scope: false, heavy: true,
        description: "全量刷新雷达维度缓存，耗时较长"
      ),

      # ── 数据质量 ──
      Task.new(
        key: "data_quality_scan", name: "数据质量扫描", group: "QUALITY", market: nil,
        service: "DataSources::DataQualityService", method_name: "scan",
        accepts_stock_scope: false, heavy: false,
        description: "扫描月K缺口/复权因子异常、财务期次不齐/空值，结果写入质量问题台账"
      )
    ].freeze

    class << self
      def all
        TASKS
      end

      def keys
        TASKS.map(&:key)
      end

      def find(key)
        TASKS.find { |task| task.key == key.to_s }
      end

      def by_group
        TASKS.group_by(&:group)
      end

      def group_name(group)
        GROUPS.fetch(group, group)
      end

      # 某数据类型对应的、支持股票子集执行的任务（后台「批量补抓」用）
      def for_data_type(data_type)
        TASKS.select { |task| task.sync_data_type == data_type.to_s && task.accepts_stock_scope? }
      end
    end
  end
end
