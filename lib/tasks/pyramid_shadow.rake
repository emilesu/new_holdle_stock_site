require "csv"

namespace :pyramid do
  desc "金字塔影子打分（不写库）：对比方案A/方案B与现行分数。" \
       "用法: rake pyramid:shadow / rake 'pyramid:shadow[CN,US]' / SAMPLE=200 rake pyramid:shadow"
  task :shadow, [:markets] => :environment do |_task, args|
    markets = if args[:markets].present?
                args[:markets].split(",").map { |m| m.strip.upcase }.select { |m| m.in?(%w[CN HK US]) }
              else
                %w[CN HK US]
              end
    abort "markets 参数不合法（仅支持 CN/HK/US）" if markets.empty?

    scope = Stock.where(market: markets).where.not(last_pyramid_calc_at: nil).order(:id)
    scope = scope.limit(ENV["SAMPLE"].to_i) if ENV["SAMPLE"].present?
    total = scope.count
    puts "🔄 影子打分开始：#{markets.join('/')} 共 #{total} 只（SAMPLE=#{ENV['SAMPLE'] || '全量'}）"

    csv_path = Rails.root.join("tmp", "pyramid_shadow_report.csv")
    rows = []
    processed = 0
    failed = 0

    CSV.open(csv_path, "w") do |csv|
      csv << %w[symbol name market sector industry old_score plan_a plan_b delta_a delta_b]

      scope.find_in_batches(batch_size: 100) do |stocks|
        preload_all_financials(stocks)

        stocks.each do |stock|
          begin
            result = DataSources::PyramidShadowService.call(stock)
            if result.nil?
              failed += 1
              next
            end

            old_score = stock.pyramid_total_score.to_i
            plan_a = result[:plan_a]
            plan_b = result[:plan_b]
            rows << {
              symbol: stock.symbol, name: stock.name, market: stock.market,
              sector: stock.sector, industry: stock.industry,
              old_score: old_score, plan_a: plan_a, plan_b: plan_b,
              delta_a: plan_a - old_score, delta_b: plan_b - old_score
            }
            csv << [stock.symbol, stock.name, stock.market, stock.sector, stock.industry,
                    old_score, plan_a, plan_b, plan_a - old_score, plan_b - old_score]
          rescue => e
            failed += 1
            Rails.logger.error "PyramidShadow error #{stock.symbol}: #{e.message}"
          end
        end

        processed += stocks.size
        puts "📈 进度: #{processed}/#{total}" if (processed / 100) % 5 == 0
      end
    end

    puts "\n✅ 完成：有效 #{rows.size} 只，跳过/失败 #{failed} 只"
    puts "📄 明细 CSV: #{csv_path}"
    print_summary(rows)
  end

  # 预加载四张财务报表（年报口径），复用 Stock 的 preloaded_* accessor
  # 与 preload_pyramid_financials 的 [nil] 哨兵约定一致，避免触发逐股查询
  def preload_all_financials(stocks)
    ids = stocks.map(&:id)
    reports = FinancialReport.where(stock_id: ids)
                             .includes(:income_statements, :balance_sheets, :cash_flows, :financial_indicators)
                             .group_by(&:stock_id)
    stocks.each do |s|
      rs = reports[s.id] || []
      annual = lambda do |assoc|
        rs.flat_map { |r| r.public_send(assoc).to_a }.select { |i| i.period_type == "annual" }
      end
      s.preloaded_income_statements = annual.call(:income_statements).presence || [nil]
      s.preloaded_balance_sheets = annual.call(:balance_sheets).presence || [nil]
      s.preloaded_cash_flows = annual.call(:cash_flows).presence || [nil]
      s.preloaded_financial_indicators = annual.call(:financial_indicators).presence || [nil]
    end
  end

  def print_summary(rows)
    return puts("无有效数据") if rows.empty?

    puts "\n════════════ 分市场统计 ════════════"
    puts format("%-6s %6s | %10s %10s %10s | %12s", "市场", "数量", "旧分均值", "方案A均值", "方案B均值", "触顶1000(旧/A/B)")
    rows.group_by { |r| r[:market] }.sort.each do |market, rs|
      old_avg = rs.sum { |r| r[:old_score] } / rs.size.to_f
      a_avg = rs.sum { |r| r[:plan_a] } / rs.size.to_f
      b_avg = rs.sum { |r| r[:plan_b] } / rs.size.to_f
      clamps = [rs.count { |r| r[:old_score] >= 1000 },
                rs.count { |r| r[:plan_a] >= 1000 },
                rs.count { |r| r[:plan_b] >= 1000 }].join("/")
      puts format("%-6s %6d | %10.1f %10.1f %10.1f | %12s", market, rs.size, old_avg, a_avg, b_avg, clamps)
    end

    puts "\n════════════ 分数变化分布 ════════════"
    %i[delta_a delta_b].each do |key|
      label = key == :delta_a ? "方案A" : "方案B"
      deltas = rows.map { |r| r[key] }
      up = deltas.count(&:positive?)
      down = deltas.count(&:negative?)
      same = deltas.count(&:zero?)
      sorted = deltas.sort
      median = sorted[sorted.size / 2]
      puts format("%s: 上升 %d / 下降 %d / 持平 %d | 变化中位数 %+d | 最大升 %+d | 最大降 %+d",
                  label, up, down, same, median, sorted.last, sorted.first)
    end

    %i[delta_a delta_b].each do |key|
      label = key == :delta_a ? "方案A" : "方案B"
      puts "\n════════════ #{label} 上升最多 Top 15 ════════════"
      print_rows(rows.max_by(15) { |r| r[key] })
      puts "\n════════════ #{label} 下降最多 Top 15 ════════════"
      print_rows(rows.min_by(15) { |r| r[key] })
    end

    puts "\n════════════ 各市场旧分 Top 15 在新方案下的变化 ════════════"
    rows.group_by { |r| r[:market] }.sort.each do |market, rs|
      puts "── #{market} ──"
      print_rows(rs.max_by(15) { |r| r[:old_score] })
    end
  end

  def print_rows(rs)
    rs.each do |r|
      puts format("%-12s %-14s 旧%4d → A%4d(%+4d) B%4d(%+4d) %s/%s",
                  r[:symbol], r[:name].to_s[0, 14], r[:old_score],
                  r[:plan_a], r[:delta_a], r[:plan_b], r[:delta_b],
                  r[:sector], r[:industry])
    end
  end
end
