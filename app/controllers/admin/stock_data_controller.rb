module Admin
  # 数据看板：各市场 × 各数据类型的覆盖率与新鲜度，支持批量补抓
  class StockDataController < BaseController
    PER_PAGE = 30
    MARKETS = %w[CN HK US].freeze
    SCOPES = %w[all missing stale failed].freeze
    SCOPE_NAMES = {
      "all" => "全部",
      "missing" => "从未同步",
      "stale" => "已过期",
      "failed" => "最近失败"
    }.freeze

    def index
      @market = MARKETS.include?(params[:market]) ? params[:market] : "CN"
      @data_type = StockDataSyncState::DATA_TYPES.include?(params[:data_type]) ? params[:data_type] : "financial"
      @scope = SCOPES.include?(params[:scope]) ? params[:scope] : "all"

      @coverages = StockDataSyncState::DATA_TYPES.index_with do |data_type|
        StockDataSyncState.coverage(market: @market, data_type: data_type)
      end

      scope = StockDataSyncState.target_stocks(market: @market, data_type: @data_type, scope: @scope)
      @page = params[:page].presence&.to_i || 1
      @page = 1 if @page < 1
      @total_count = scope.count
      @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
      @stocks = scope.order(:symbol).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      @sync_states = StockDataSyncState
        .where(stock_id: @stocks.map(&:id), data_type: @data_type)
        .index_by(&:stock_id)
      @task = recrawl_task_for(@market, @data_type)
    end

    # 批量补抓：把看板筛选条件翻译成任务参数入队
    def recrawl
      market = params[:market].to_s
      data_type = params[:data_type].to_s
      scope = params[:scope].to_s
      selected_ids = Array(params[:stock_ids]).map(&:to_i).uniq

      # 必须拦住空勾选：空数组会被 CrawlerScope 视为「未指定股票」而退化成全市场补抓
      if scope == "selected" && selected_ids.empty?
        redirect_to admin_stock_data_path(market: market, data_type: data_type, scope: scope),
                    alert: "请先勾选需要补抓的股票"
        return
      end

      task = recrawl_task_for(market, data_type)
      unless task
        redirect_to admin_stock_data_path(market: market, data_type: data_type, scope: scope),
                    alert: "「#{StockDataSyncState.data_type_name(data_type)}」在 #{market} 市场暂无支持按股票子集补抓的任务，请到爬虫管理页执行全量任务"
        return
      end

      execution = DataSources::CrawlerExecutionStarter.call(
        task: task,
        trigger_source: "manual",
        params: recrawl_params(market, data_type, scope, selected_ids)
      )
      redirect_to admin_crawler_execution_path(execution),
                  notice: "已提交「#{task.name}」补抓任务（记录 ##{execution.id}），可在本页查看执行进度"
    end

    private

    # 该市场该类型下，支持股票子集补抓的任务；无市场专属任务时回退到跨市场任务
    def recrawl_task_for(market, data_type)
      candidates = DataSources::CrawlerRegistry.for_data_type(data_type)
      candidates.find { |task| task.market == market } || candidates.find { |task| task.market.blank? }
    end

    def recrawl_params(market, data_type, scope, selected_ids)
      case scope
      when "selected"
        { stock_ids: selected_ids }
      when "all"
        # 全量交给 CrawlerScope 按市场解析，避免把成千上万个 id 写进执行参数
        {}
      else
        # missing / stale / failed：服务端把目标股票解析成显式 id 列表，
        # 不同任务对 stale_after / only_failed 的支持不一，显式 id 才能保证补抓范围与页面所见一致
        { stock_ids: StockDataSyncState.target_stocks(market: market, data_type: data_type, scope: scope).pluck(:id) }
      end
    end
  end
end
