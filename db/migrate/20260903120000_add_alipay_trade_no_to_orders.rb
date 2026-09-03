class AddAlipayTradeNoToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :alipay_trade_no, :string, comment: "支付宝交易号"
  end
end