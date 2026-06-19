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
    unless lesson.published?
      redirect_to courses_path, alert: '该小节尚未发布'
      return
    end
    course = lesson.course
    unless course.published?
      redirect_to courses_path, alert: '该课程尚未发布'
      return
    end
    unless lesson.available_to?(current_user)
      redirect_to courses_path, alert: '该内容仅限会员访问，请升级会员'
    end
  end
end