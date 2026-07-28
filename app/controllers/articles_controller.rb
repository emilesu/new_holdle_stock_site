class ArticlesController < ApplicationController
  before_action :authenticate_user!, except: [:index]
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
    unless @article.available_to?(current_user)
      redirect_to articles_path, alert: '该内容仅限会员访问，请升级会员'
    end
  end
end
