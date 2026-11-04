class ArticlesController < ApplicationController
  # 文章列表与公开文章详情无需登录即可查看，会员文章仍通过 check_access 拦截
  before_action :check_access, only: [:show]

  def index
    @articles = Article.published.sorted.accessible_by(current_user)
  end

  def show
    @article = Article.published.find(params[:id])
  end

  private

  def check_access
    @article = Article.find(params[:id])
    unless @article.published?
      redirect_to articles_path, alert: '该文章尚未发布'
      return
    end
    # 非公开文章（学员档 / 会员档）都要求先登录
    if !@article.public? && !user_signed_in?
      store_return_to_location(request.fullpath)
      redirect_to new_user_session_path, alert: '该文章需登录访问（课程学员 / 会员可解锁），请先登录'
      return
    end
    unless @article.available_to?(current_user)
      hint = @article.student_only? ? '该内容为课程学员专属，¥268 开通后可见' : '该内容仅限会员访问，请升级会员'
      redirect_to articles_path, alert: hint
    end
  end
end
