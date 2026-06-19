class AddAccessLevelToChaptersAndLessonsAndCoverToCourses < ActiveRecord::Migration[7.1]
  def change
    add_column :courses, :cover, :string, comment: "封面图片URL"
    add_column :chapters, :access_level, :integer, comment: "访问级别（null=继承课程，0=公开，1=会员）"
    add_column :lessons, :access_level, :integer, comment: "访问级别（null=继承章节，0=公开，1=会员）"
  end
end