class CoursesController < ApplicationController
  before_action :authenticate_user!
  before_action :check_access, only: [:show]

  def index
    @courses = Course.published.sorted
  end

  def show
    @course = Course.published.find(params[:id])
    @chapters = @course.chapters.published.sorted.includes(:lessons)
  end

  private

  def check_access
    @course = Course.find(params[:id])
    unless @course.published?
      redirect_to courses_path, alert: '该课程尚未发布'
      return
    end
    unless @course.available_to?(current_user)
      redirect_to courses_path, alert: '该课程仅限会员访问，请升级会员'
    end
  end
end