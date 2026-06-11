class CreateLessons < ActiveRecord::Migration[7.1]
  def change
    create_table :lessons do |t|
      t.belongs_to :chapter, null: false, foreign_key: true
      t.string :title
      t.text :content
      # 加默认值 0
      t.integer :sort_num, default: 0
      # 加默认值 false
      t.boolean :is_published, default: false

      t.timestamps
    end
  end
end
