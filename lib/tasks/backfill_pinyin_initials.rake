# frozen_string_literal: true

namespace :stocks do
  desc "回填现有 CN/HK 股票的中文名拼音首字母"
  task backfill_pinyin: :environment do
    scope = Stock.where(market: %w[CN HK]).where.not(name: [nil, ""])
    total = scope.count
    puts "开始回填拼音首字母，共 #{total} 条..."

    scope.find_each.with_index do |stock, i|
      initials = Pinyin.t(stock.name).split.map(&:first).join.upcase
      stock.update_column(:pinyin_initials, initials) if stock.pinyin_initials != initials
      puts "  [#{i + 1}/#{total}] #{stock.symbol} #{stock.name} -> #{initials}" if (i % 100).zero?
    end

    puts "回填完成，共 #{total} 条"
  end
end
