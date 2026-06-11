class CreateChapters < ActiveRecord::Migration[7.1]
  def change
    create_table :chapters do |t|
      t.string :title
      t.text :summary
      # 加默认值 0
      t.integer :sort_num, default: 0
      # 加默认值 false
      t.boolean :is_published, default: false

      t.timestamps
    end
  end
end
