module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :edit, :update, :destroy,
                                    :adjust_api_key_quota, :disable_api_key, :enable_api_key, :regenerate_api_key]

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

    # ===== T7 Phase2：AI 投研 KEY 管理（操作全在 edit 页，show 页只展示） =====

    # 调整次数（补偿）：仅有限次 key 可调；无限次会员 key 不允许
    def adjust_api_key_quota
      key = @user.api_keys.active.first
      delta = params[:delta].to_i
      reason = params[:reason].to_s.strip

      if key.nil?
        redirect_to edit_admin_user_path(@user), alert: '该用户没有 active key'
      elsif key.unlimited?
        redirect_to edit_admin_user_path(@user), alert: '无限次会员 key 无需调整次数'
      elsif delta.zero?
        redirect_to edit_admin_user_path(@user), alert: '调整数量不能为 0'
      else
        key.adjust_quota!(delta: delta, admin: current_user, reason: reason.presence || '管理员调整')
        redirect_to edit_admin_user_path(@user), notice: "已调整 #{delta.positive? ? '+' : ''}#{delta} 次"
      end
    end

    # 停用 key（防泄露/违规，可恢复）
    def disable_api_key
      @user.api_keys.active.first&.disable!(reason: '管理员停用')
      redirect_to edit_admin_user_path(@user), notice: 'key 已停用'
    end

    # 启用 key（恢复）
    def enable_api_key
      @user.api_keys.where(status: 'disabled').first&.enable!
      redirect_to edit_admin_user_path(@user), notice: 'key 已启用'
    end

    # 重新生成 key：吊销旧 key + 按原套餐生成新 key（明文仅展示一次）
    def regenerate_api_key
      old = @user.api_keys.active.first
      if old.nil?
        redirect_to edit_admin_user_path(@user), alert: '该用户没有 active key 可重新生成'
        return
      end

      plan = Plan.find_by!(plan_code: old.plan_code)
      plain = nil
      ok = ApiKey.transaction do
        old.update!(status: 'revoked')
        plain = ApiKey.generate!(user: @user, plan: plan)
        raise ActiveRecord::Rollback unless plain
        true
      end

      if ok
        redirect_to edit_admin_user_path(@user), notice: "新 key 已生成（仅此一次展示）：#{plain}"
      else
        redirect_to edit_admin_user_path(@user), alert: '重新生成失败，请重试'
      end
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
      # 管理员后台：允许更新角色/会员到期时间等敏感字段（安全通过 Pundit 鉴权）
      params.require(:user).permit(:email, :nickname, :role, :member_expire_at, :bio)
    end
  end
end
