class LessonsController < ApplicationController
  # 公开小节无需登录即可查看，会员小节仍通过 check_access 拦截
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
    if lesson.member_only? && !user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path, alert: '该小节仅限会员访问，请先登录'
      return
    end
    unless lesson.available_to?(current_user)
      redirect_to courses_path, alert: '该内容仅限会员访问，请升级会员'
    end
  end
end