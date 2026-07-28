class CreateArticles < ActiveRecord::Migration[7.1]
  def change
    create_table :articles, comment: 'AI复盘报告文章表' do |t|
      t.string :title, null: false, comment: '文章标题'
      t.text :summary, comment: '简介/摘要'
      t.text :content, comment: 'Markdown 正文内容'
      t.boolean :is_published, default: false, comment: '发布状态(false=草稿, true=发布)'
      t.integer :access_level, default: 0, comment: '访问级别(0=公开, 1=会员)'
      t.integer :sort, default: 0, comment: '排序权重'
      t.datetime :published_at, comment: '发布时间'

      t.timestamps
    end

    add_index :articles, :published_at
  end
end
