namespace :pyramid do
  desc "按平均资产周转率定向重算金字塔分。用法: rake 'pyramid:recalc_by_turnover[CN,0.8,5]'（markets=CN/HK/US 逗号分隔, threshold=次, years=年报窗口年数）"
  task :recalc_by_turnover, %i[markets threshold years] => :environment do |_task, args|
    markets = (args[:markets] || "CN").split(",").map { |m| m.strip.upcase }.select { |m| %w[CN HK US].include?(m) }
    abort "markets 参数为空或不合法（仅支持 CN/HK/US）" if markets.empty?
    threshold = (args[:threshold] || 0.8).to_f
    years = (args[:years] || 5).to_i
    y_to = Date.current.year
    y_from = y_to - years

    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL, { markets: markets, y_from: y_from, y_to: y_to, threshold: threshold }])
      WITH yr AS (
        SELECT s.id AS stock_id, i.total_revenue / NULLIF(b.total_assets, 0) AS turnover
        FROM stocks s
        JOIN income_statements i ON i.stock_id = s.id AND i.period_type = 'annual'
          AND EXTRACT(YEAR FROM i.report_date) BETWEEN :y_from AND :y_to
        JOIN balance_sheets b ON b.stock_id = s.id AND b.period_type = 'annual'
          AND b.report_date = i.report_date AND b.total_assets IS NOT NULL AND b.total_assets <> 0
        WHERE s.market IN (:markets) AND s.last_pyramid_calc_at IS NOT NULL
      ), agg AS (
        SELECT stock_id, COUNT(*) cnt, AVG(turnover) avg_t FROM yr GROUP BY stock_id
      )
      SELECT a.stock_id FROM agg a WHERE a.cnt >= #{years} AND a.avg_t > :threshold
    SQL

    ids = ActiveRecord::Base.connection.select_values(sql)
    puts "待重算: #{ids.size} 只 (markets=#{markets.join(",")} 近#{years}年平均周转 > #{threshold} 次)"
    stats = DataSources::StockPyramidBatchService.call(stock_ids: ids)
    puts "统计: #{stats.inspect}"
  end
end
