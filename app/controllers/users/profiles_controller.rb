class Users::ProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  after_action :verify_authorized

  def show
    authorize @user
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    if @user.update(user_params)
      redirect_to users_profile_path, notice: "个人信息更新成功"
    else
      render :edit
    end
  rescue StandardError => e
    flash[:alert] = "更新失败：#{e.message}"
    render :edit
  end

  def update_password
    authorize @user, :update_password?
    if @user.update_with_password(password_params)
      bypass_sign_in(@user)
      redirect_to users_profile_path, notice: "密码修改成功"
    else
      render :edit
    end
  rescue StandardError => e
    flash[:alert] = "密码修改失败：#{e.message}"
    render :edit
  end

  def favorites
    authorize @user
    @favorites = UserFavorite.where(user: @user).includes(:stock).order(created_at: :desc).page(params[:page]).per(20)
  end

  private

  def set_user
    @user = current_user
  end

  def user_params
    params.require(:user).permit(:nickname, :bio)
  end

  def password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end
end
