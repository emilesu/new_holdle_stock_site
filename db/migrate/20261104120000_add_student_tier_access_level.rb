class AddStudentTierAccessLevel < ActiveRecord::Migration[7.1]
  # 课程学员（268）档位上线：access_level 从二元（0=公开 1=会员）改为三级阶梯
  # 0=公开 / 1=学员可见 / 2=会员专属。存量"会员"内容整体升档为 2，为学员档腾出 1。
  # 必须与模型门控代码同批上线；上线时学员尚不存在，无越权窗口。
  TABLES = %w[courses chapters lessons articles].freeze

  def up
    TABLES.each do |table|
      count = connection.select_value("SELECT COUNT(*) FROM #{table} WHERE access_level = 1").to_i
      say "#{table}: #{count} 行 access_level 1 → 2"
      connection.execute("UPDATE #{table} SET access_level = 2 WHERE access_level = 1")
    end

    change_column_comment :articles, :access_level, "访问级别(0=公开, 1=学员, 2=会员)"
    change_column_comment :courses, :access_level, "访问级别(0=公开, 1=学员, 2=会员)"
    change_column_comment :chapters, :access_level, "访问级别（null=继承课程，0=公开，1=学员，2=会员）"
    change_column_comment :lessons, :access_level, "访问级别（null=继承章节，0=公开，1=学员，2=会员）"
  end

  def down
    TABLES.each do |table|
      connection.execute("UPDATE #{table} SET access_level = 1 WHERE access_level = 2")
    end

    change_column_comment :articles, :access_level, "访问级别(0=公开, 1=会员)"
    change_column_comment :courses, :access_level, "访问级别(0=公开, 1=会员)"
    change_column_comment :chapters, :access_level, "访问级别（null=继承课程，0=公开，1=会员）"
    change_column_comment :lessons, :access_level, "访问级别（null=继承章节，0=公开，1=会员）"
  end
end
