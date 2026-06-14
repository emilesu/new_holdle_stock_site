module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :edit, :update, :destroy]

    def index
      @users = User.order(created_at: :desc)
      
      if params[:search].present?
        @users = @users.where("email ILIKE ? OR nickname ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
      end
      
      if params[:role].present? && params[:role] != 'all'
        @users = @users.where(role: params[:role])
      end
      
      @per_page = 20
      @page = params[:page] ? params[:page].to_i : 1
      @total_count = @users.count
      @total_pages = (@total_count.to_f / @per_page).ceil
      @users = @users.offset((@page - 1) * @per_page).limit(@per_page)
    end

    def show
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      @user.password = SecureRandom.hex(8)
      
      if @user.save
        redirect_to admin_user_path(@user), notice: '用户创建成功，初始密码已发送至邮箱'
      else
        flash[:alert] = "创建失败：#{@user.errors.full_messages.join(', ')}"
        render :new
      end
    rescue StandardError => e
      flash[:alert] = "创建失败：#{e.message}"
      render :new
    end

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: '用户信息更新成功'
      else
        flash[:alert] = "更新失败：#{@user.errors.full_messages.join(', ')}"
        render :edit
      end
    rescue StandardError => e
      flash[:alert] = "更新失败：#{e.message}"
      render :edit
    end

    def destroy
      if current_user == @user
        redirect_to admin_users_path, alert: '不能删除自己的账号'
        return
      end
      
      if @user.destroy
        redirect_to admin_users_path, notice: '用户已删除'
      else
        redirect_to admin_users_path, alert: "删除失败：#{@user.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      redirect_to admin_users_path, alert: "删除失败：#{e.message}"
    end

    private

    def set_user
      @user = User.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_users_path, alert: '用户不存在'
    end

    def user_params
      params.require(:user).permit(:email, :nickname, :role, :member_expire_at, :bio)
    end
  end
end
