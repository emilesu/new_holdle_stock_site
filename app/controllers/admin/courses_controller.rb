# module Admin
#   class CoursesController < BaseController
#     def index
#       @courses = Course.order(created_at: :desc).page(params[:page]).per(20)
#     end

#     def new
#       @course = Course.new
#     end

#     def create
#       @course = Course.new(course_params)
#       if @course.save
#         redirect_to admin_course_path(@course), notice: "课程创建成功"
#       else
#         render :new
#       end
#     rescue StandardError => e
#       flash[:alert] = "创建失败：#{e.message}"
#       render :new
#     end

#     def show
#       @course = Course.find(params[:id])
#     end

#     def edit
#       @course = Course.find(params[:id])
#     end

#     def update
#       @course = Course.find(params[:id])
#       if @course.update(course_params)
#         redirect_to admin_course_path(@course), notice: "课程信息更新成功"
#       else
#         render :edit
#       end
#     rescue StandardError => e
#       flash[:alert] = "更新失败：#{e.message}"
#       render :edit
#     end

#     def destroy
#       @course = Course.find(params[:id])
#       @course.destroy
#       redirect_to admin_courses_path, notice: "课程已删除"
#     rescue StandardError => e
#       flash[:alert] = "删除失败：#{e.message}"
#       redirect_to admin_courses_path
#     end

#     private

#     def course_params
#       params.require(:course).permit(:title, :category, :status, :price, :cover_image, :description)
#     end
#   end
# end
# 待开发
