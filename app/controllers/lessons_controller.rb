class LessonsController < ApplicationController
  before_action :authenticate_user!
  before_action :check_access

  def show
    @lesson = Lesson.published.includes(:chapter).find(params[:id])
    @chapter = @lesson.chapter
    @course = @chapter.course
  end

  private

  def check_access
    lesson = Lesson.find(params[:id])
    course = lesson.chapter.course
    unless course.published?
      redirect_to courses_path, alert: '该课程尚未发布'
      return
    end
    if course.member_only? && !current_user.is_member?
      redirect_to courses_path, alert: '该课程仅限会员访问，请升级会员'
    end
  end
end