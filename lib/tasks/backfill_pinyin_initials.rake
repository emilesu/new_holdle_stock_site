# frozen_string_literal: true

namespace :stocks do
  desc "回填所有股票的中文名拼音首字母（CN/HK 全名，US 取 | 前的部分）"
  task backfill_pinyin: :environment do
    # CN/HK 股票：直接用 name 转拼音首字母
    cn_hk = Stock.where(market: %w[CN HK]).where.not(name: [nil, ""])
    puts "CN/HK 股票 #{cn_hk.count} 条..."
    cn_hk.find_each.with_index do |stock, i|
      initials = Pinyin.t(stock.name).split.map(&:first).join.upcase
      stock.update_column(:pinyin_initials, initials) if stock.pinyin_initials != initials
      puts "  CN/HK [#{i + 1}] #{stock.symbol} -> #{initials}" if (i % 200).zero?
    end

    # US 股票：仅处理含中文名（含 | 分隔符）的股票
    us = Stock.where(market: 'US').where("name LIKE ?", "%|%").where.not(name: [nil, ""])
    puts "US 股票（有中文名） #{us.count} 条..."
    us.find_each.with_index do |stock, i|
      chinese_part = stock.name.split('|').first.strip
      initials = Pinyin.t(chinese_part).split.map(&:first).join.upcase
      stock.update_column(:pinyin_initials, initials) if stock.pinyin_initials != initials
      puts "  US [#{i + 1}] #{stock.symbol} #{chinese_part} -> #{initials}" if (i % 200).zero?
    end

    puts "回填完成！"
  end
end
