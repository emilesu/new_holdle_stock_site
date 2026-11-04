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
      hint = @course.student_only? ? '该内容为课程学员专属，¥268 开通后可见' : '该课程仅限会员访问，请升级会员'
      redirect_to courses_path, alert: hint
    end
  end
end