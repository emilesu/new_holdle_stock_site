class CoursesController < ApplicationController
  # 课程列表与公开课程详情无需登录即可查看，会员课程仍通过 check_access 拦截
  before_action :check_access, only: [:show]

  def index
    @courses = Course.published.sorted.includes(:chapters, :lessons)
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
    if @course.member_only? && !user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path, alert: '该课程仅限会员访问，请先登录'
      return
    end
    unless @course.available_to?(current_user)
      redirect_to courses_path, alert: '该课程仅限会员访问，请升级会员'
    end
  end
end