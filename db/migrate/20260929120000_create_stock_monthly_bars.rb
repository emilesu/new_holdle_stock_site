class CreateStockMonthlyBars < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_monthly_bars, comment: '股票月K线数据表（含前复权/后复权两套价格）' do |t|
      t.bigint :stock_id, null: false, comment: '股票ID，关联stocks表'
      t.string :market, null: false, default: "CN", comment: '市场类型'
      t.date :trade_date, null: false, comment: '月末交易日'

      t.decimal :open, precision: 12, scale: 4, comment: '不复权开盘价（溯源用，不直接展示）'
      t.decimal :close, precision: 12, scale: 4, comment: '不复权收盘价（溯源用，不直接展示）'
      t.decimal :high, precision: 12, scale: 4, comment: '不复权最高价（溯源用，不直接展示）'
      t.decimal :low, precision: 12, scale: 4, comment: '不复权最低价（溯源用，不直接展示）'
      t.bigint :volume, comment: '成交量'

      t.decimal :qfq_open, precision: 12, scale: 4, comment: '前复权开盘价（默认展示口径）'
      t.decimal :qfq_close, precision: 12, scale: 4, comment: '前复权收盘价（默认展示口径）'
      t.decimal :qfq_high, precision: 12, scale: 4, comment: '前复权最高价（默认展示口径）'
      t.decimal :qfq_low, precision: 12, scale: 4, comment: '前复权最低价（默认展示口径）'

      t.decimal :hfq_open, precision: 12, scale: 4, comment: '后复权开盘价（可切换展示，亦为MACD递推基准）'
      t.decimal :hfq_close, precision: 12, scale: 4, comment: '后复权收盘价（可切换展示，亦为MACD递推基准）'
      t.decimal :hfq_high, precision: 12, scale: 4, comment: '后复权最高价（可切换展示，亦为MACD递推基准）'
      t.decimal :hfq_low, precision: 12, scale: 4, comment: '后复权最低价（可切换展示，亦为MACD递推基准）'

      t.decimal :qfq_factor, precision: 20, scale: 10, comment: '该月适用的前复权因子'
      t.decimal :hfq_factor, precision: 20, scale: 10, comment: '该月适用的后复权因子'

      t.timestamps
    end

    add_index :stock_monthly_bars, [:stock_id, :trade_date], unique: true
    add_index :stock_monthly_bars, [:market, :trade_date]
    add_foreign_key :stock_monthly_bars, :stocks
  end
end