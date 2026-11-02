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
  end
end
