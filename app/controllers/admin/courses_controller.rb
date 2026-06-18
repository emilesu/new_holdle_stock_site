module Admin
  class CoursesController < BaseController
    before_action :set_course, only: [:show, :edit, :update, :destroy]

    def index
      @courses = Course.sorted
    end

    def show
      @chapters = @course.chapters.includes(:lessons).sorted
    end

    def new
      @course = Course.new
    end

    def create
      @course = Course.new(course_params)
      if @course.save
        redirect_to admin_courses_path, notice: '课程创建成功'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @course.update(course_params)
        redirect_to admin_courses_path, notice: '课程更新成功'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @course.destroy
      redirect_to admin_courses_path, notice: '课程已删除'
    end

    private

    def set_course
      @course = Course.find(params[:id])
    end

    def course_params
      params.require(:course).permit(:title, :description, :is_published, :access_level, :sort)
    end
  end
end