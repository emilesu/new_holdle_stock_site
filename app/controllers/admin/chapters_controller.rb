module Admin
  class ChaptersController < BaseController
    before_action :set_course
    before_action :set_chapter, only: [:show, :edit, :update, :destroy]

    def index
      @chapters = @course.chapters.sorted
    end

    def show
      @lessons = @chapter.lessons.sorted
    end

    def new
      @chapter = @course.chapters.new
    end

    def create
      @chapter = @course.chapters.new(chapter_params)
      if @chapter.save
        redirect_to admin_course_chapters_path(@course), notice: '章节创建成功'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @chapter.update(chapter_params)
        redirect_to admin_course_chapters_path(@course), notice: '章节更新成功'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @chapter.destroy
      redirect_to admin_course_chapters_path(@course), notice: '章节已删除'
    end

    private

    def set_course
      @course = Course.find(params[:course_id])
    end

    def set_chapter
      @chapter = @course.chapters.find(params[:id])
    end

    def chapter_params
      params.require(:chapter).permit(:title, :summary, :sort_num, :is_published)
    end
  end
end