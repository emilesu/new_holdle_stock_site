class AddCourseIdToChapters < ActiveRecord::Migration[7.1]
  def change
    add_reference :chapters, :course, null: false, foreign_key: true
  end
end
