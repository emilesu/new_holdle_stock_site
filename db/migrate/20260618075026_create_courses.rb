class CreateCourses < ActiveRecord::Migration[7.1]
  def change
    create_table :courses do |t|
      t.string :title, null: false
      t.text :description
      t.boolean :is_published, default: false
      t.integer :access_level, default: 0  # 0=登录可见 1=会员可见
      t.integer :sort, default: 0

      t.timestamps
    end
  end
end
