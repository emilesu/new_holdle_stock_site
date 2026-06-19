module Admin
  class LessonsController < BaseController
    before_action :set_course_and_chapter
    before_action :set_lesson, only: [:show, :edit, :update, :destroy]

    def index
      @lessons = @chapter.lessons.sorted
    end

    def show
    end

    def new
      @lesson = @chapter.lessons.new
    end

    def create
      @lesson = @chapter.lessons.new(lesson_params)
      if @lesson.save
        redirect_to admin_course_chapter_lessons_path(@course, @chapter), notice: '小节创建成功'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @lesson.update(lesson_params)
        redirect_to admin_course_chapter_lessons_path(@course, @chapter), notice: '小节更新成功'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @lesson.destroy
      redirect_to admin_course_chapter_lessons_path(@course, @chapter), notice: '小节已删除'
    end

    private

    def set_course_and_chapter
      @course = Course.find(params[:course_id])
      @chapter = @course.chapters.find(params[:chapter_id])
    end

    def set_lesson
      @lesson = @chapter.lessons.find(params[:id])
    end

    def lesson_params
      params.require(:lesson).permit(:title, :content, :sort_num, :is_published, :access_level)
    end
  end
end