class CreateBaiduPushTables < ActiveRecord::Migration[7.1]
  def change
    # 已推送 URL 去重/审计表（唯一索引保证同一 URL 只推一次）
    create_table :baidu_push_urls do |t|
      t.string :url, null: false, comment: "已推送的绝对 URL"
      t.datetime :pushed_at, null: false, comment: "推送成功时间"
      t.timestamps
    end
    add_index :baidu_push_urls, :url, unique: true

    # 当日配额/超配额状态（单例记录，id 恒为 1）
    create_table :baidu_push_states do |t|
      t.date :push_date, null: false, comment: "对应配额日期"
      t.integer :remain, default: 0, comment: "当日剩余可推条数（百度返回）"
      t.boolean :over_quota, default: false, null: false, comment: "当日是否已超配额"
      t.timestamps
    end
  end
end