class AddFieldsToFinancialReports < ActiveRecord::Migration[7.1]
  def change
    add_column :financial_reports, :market, :string, default: "US", null: false, comment: '市场类型（US/A股等）'
    add_column :financial_reports, :status, :string, default: "pending", comment: '爬取状态（pending/success/failed）'
    add_column :financial_reports, :retry_count, :integer, default: 0, comment: '重试次数'
    add_column :financial_reports, :last_crawled_at, :datetime, comment: '最后爬取时间'

    add_index :financial_reports, :market
  end
end