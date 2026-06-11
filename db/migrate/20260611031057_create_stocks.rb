class CreateStocks < ActiveRecord::Migration[7.1]
  def change
    create_table :stocks do |t|
      t.string :symbol
      t.string :name
      t.string :market
      t.string :industry
      t.string :exchange
      t.string :status

      t.timestamps
    end

    # 加联合唯一索引
    add_index :stocks, [:symbol, :market], unique: true
  end
end
