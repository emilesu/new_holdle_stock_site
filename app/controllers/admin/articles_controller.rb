module Admin
  class ArticlesController < BaseController
    before_action :set_article, only: [:show, :edit, :update, :destroy]

    def index
      @articles = Article.sorted
    end

    def show
    end

    def new
      @article = Article.new
    end

    def create
      @article = Article.new(article_params)
      @article.published_at ||= Time.current if @article.is_published
      if @article.save
        redirect_to admin_articles_path, notice: '文章创建成功'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @article.assign_attributes(article_params)
      @article.published_at ||= Time.current if @article.is_published
      if @article.save
        redirect_to admin_articles_path, notice: '文章更新成功'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @article.destroy
      redirect_to admin_articles_path, notice: '文章已删除'
    end

    private

    def set_article
      @article = Article.find(params[:id])
    end

    def article_params
      params.require(:article).permit(:title, :summary, :content, :is_published, :access_level, :sort, :published_at)
    end
  end
end
