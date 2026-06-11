class CreateFinancialReports < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_reports do |t|
      t.belongs_to :stock, null: false, foreign_key: true
      t.date :report_date
      t.string :report_type
      t.string :currency

      t.timestamps
    end

    # 加联合索引
    add_index :financial_reports, [:stock_id, :report_date, :report_type], unique: true
  end
end
