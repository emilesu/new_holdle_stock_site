class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.string :order_no, null: false
      t.references :user, null: false, foreign_key: true
      t.string :product_code, null: false, default: "member_permanent"
      t.string :title, null: false, default: "HOLD LE 永久会员"
      t.integer :amount_cents, null: false, default: 46800
      t.string :currency, default: "cny"
      t.string :payment_method
      t.string :status, null: false, default: "pending"
      t.string :prepay_id
      t.string :code_url
      t.string :wechat_transaction_id
      t.datetime :paid_at
      t.jsonb :notify_raw
      t.datetime :expire_at
      t.timestamps
    end

    add_index :orders, :order_no, unique: true
    add_index :orders, :status
  end
end
