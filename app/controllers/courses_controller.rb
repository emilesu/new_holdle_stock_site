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
    # 非公开内容（学员档 / 会员档）都要求先登录
    if !@course.public? && !user_signed_in?
      store_return_to_location(request.fullpath)
      redirect_to new_user_session_path, alert: '该课程需登录访问（课程学员 / 会员可解锁），请先登录'
      return
    end
    unless @course.available_to?(current_user)
      redirect_to courses_path, alert: helpers.tier_unlock_hint(@course.access_level)
    end
  end
end