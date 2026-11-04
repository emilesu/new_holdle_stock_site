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
    # 非公开小节（学员档 / 会员档）都要求先登录
    if !lesson.public? && !user_signed_in?
      store_return_to_location(request.fullpath)
      redirect_to new_user_session_path, alert: '该小节需登录访问（课程学员 / 会员可解锁），请先登录'
      return
    end
    unless lesson.available_to?(current_user)
      hint = lesson.student_only? ? '该内容为课程学员专属，¥268 开通后可见' : '该内容仅限会员访问，请升级会员'
      redirect_to courses_path, alert: hint
    end
  end
end