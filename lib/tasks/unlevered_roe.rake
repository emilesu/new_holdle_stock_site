namespace :unlevered_roe do
  desc "按已入库科目重算无杠杆ROE（纯本地计算不重爬；调口径/新指标上线后全量刷新用）"
  task :recalculate, [:market] => :environment do |_task, args|
    market = args[:market] || "CN"
    total_stocks = 0
    total_updated = 0
    Stock.where(market: market).find_each do |stock|
      result = DataSources::UnleveredRoeService.call(stock: stock, market: market)
      total_stocks += 1
      total_updated += result[:updated]
      print "." if stock.id % 100 == 0
    end
    puts "\n[unlevered_roe] #{market} 重算完成：#{total_stocks} 只股票，更新 #{total_updated} 条指标记录"
    puts "[unlevered_roe] 提示：历史期次的有息负债/归母净资产科目需重爬 a_finance 才会入库，"
    puts "               未重爬的期次 flag=1 显示为 —，属预期行为"
    puts "[unlevered_roe] 美股请改用 unlevered_roe:backfill_us 分批补抓科目" if market == "US"
  end

  desc "美股：补抓利润表/资产负债表新科目并重算无杠杆ROE（分批，LIMIT/OFFSET/SYMBOLS）"
  task backfill_us: :environment do
    limit = ENV.fetch("LIMIT", "200").to_i
    offset = ENV.fetch("OFFSET", "0").to_i
    symbols = ENV["SYMBOLS"].to_s.split(",").map(&:strip).reject(&:empty?)

    scope = Stock.where(market: "US")
    if symbols.any?
      scope = scope.where(symbol: symbols)
    else
      # 只处理库内已有财务记录的股票；其余标的没有可对齐的期次，等常规抓取先建报表
      ids = (FinancialIndicator.where(market: "US").distinct.pluck(:stock_id) +
             BalanceSheet.where(market: "US").distinct.pluck(:stock_id) +
             IncomeStatement.where(market: "US").distinct.pluck(:stock_id)).uniq
      scope = scope.where(id: ids)
    end

    stocks = scope.order(:id).offset(offset).limit(limit).to_a
    if stocks.empty?
      puts "[unlevered_roe:backfill_us] 没有待处理股票（OFFSET=#{offset}）"
      next
    end

    fetcher = DataSources::Fetchers::UsFetcher.new
    stats = Hash.new(0)
    stocks.each_with_index do |stock, index|
      result = fetcher.backfill_unlevered_roe(stock)
      stats[result[:status]] += 1
      detail = result[:reason].present? ? " (#{result[:reason]})" : ""
      puts "[#{index + 1}/#{stocks.size}] #{stock.symbol} #{result[:status]} updated=#{result[:updated]}#{detail}"
      sleep 0.3
    rescue => e
      stats[:error] += 1
      puts "[#{index + 1}/#{stocks.size}] #{stock.symbol} 异常: #{e.message}"
    end

    ids = stocks.map(&:id)
    flag_counts = FinancialIndicator.where(market: "US", stock_id: ids)
                                     .group(:unlevered_roe_flag).count
    puts "[unlevered_roe:backfill_us] 批次完成: #{stats.inspect}"
    # flag 可能为 nil（未计算），排序时按 -1 处理，避免 nil 与整数比较报错
    sorted_flags = flag_counts.sort_by { |flag, _count| flag.nil? ? -1 : flag }.to_h
    puts "[unlevered_roe:backfill_us] flag 分布: #{sorted_flags.inspect}"
    puts "[unlevered_roe:backfill_us] 下一批：OFFSET=#{offset + stocks.size} LIMIT=#{limit}"
  end
end
