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
    if @article.member_only? && !user_signed_in?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path, alert: '该文章仅限会员访问，请先登录'
      return
    end
    unless @article.available_to?(current_user)
      redirect_to articles_path, alert: '该内容仅限会员访问，请升级会员'
    end
  end
end
