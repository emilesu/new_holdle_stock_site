class CreateCrawlerExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :crawler_executions do |t|
      t.string :task_name, null: false
      t.string :status, null: false, default: 'success'
      t.string :message
      t.decimal :duration, precision: 10, scale: 2
      t.datetime :executed_at, null: false

      t.timestamps
    end

    add_index :crawler_executions, :executed_at
  end
end