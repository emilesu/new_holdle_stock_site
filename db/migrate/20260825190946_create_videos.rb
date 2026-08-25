class CreateVideos < ActiveRecord::Migration[7.1]
  def change
    create_table :videos, comment: "视频展示" do |t|
      t.string   :title,        null: false, comment: "视频标题"
      t.string   :cover_url,    comment: "封面图 URL"
      t.string   :bilibili_url, comment: "B站视频链接"
      t.string   :youtube_url,  comment: "YouTube 视频链接"
      t.boolean  :is_published, default: false, comment: "是否发布"
      t.integer  :sort,         default: 0, comment: "排序（越小越前）"
      t.datetime :published_at, comment: "发布时间"

      t.timestamps
    end

    add_index :videos, :sort
  end
end
