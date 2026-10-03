class Admin::MessagesController < Admin::BaseController
  PER_PAGE = 20
  THREAD_PER_PAGE = 50 # 会话详情正序分页，与 show/reply 共用

  # 会话列表：按用户聚合（最后消息时间倒序），带未读数与最后一条预览
  def index
    page = (params[:page] || 1).to_i
    @page = page
    @threads = Message.normal
                      .group(:user_id)
                      .order(Arel.sql("MAX(created_at) DESC"))
                      .offset((page - 1) * PER_PAGE)
                      .limit(PER_PAGE)
                      .pluck(:user_id, Arel.sql("MAX(created_at)"))
    @has_prev = page > 1
    @has_next = @threads.size == PER_PAGE

    uids = @threads.map(&:first)
    @users = User.where(id: uids).index_by(&:id)
    @unread_counts = Message.unread_for_admin.group(:user_id).count
    # 各会话最后一条消息预览：一次取齐后按用户分组取末条，避免逐行查询
    previews = Message.normal.where(user_id: uids).order(:created_at, :id).pluck(:user_id, :sender, :content)
    @previews = previews.group_by(&:first).transform_values(&:last)
  end

  # 会话详情：该用户全部消息正序分页（含已隐藏的可恢复），进入即把用户消息标记已读
  def show
    @user = User.find(params[:user_id])
    @messages = @user.messages.order(created_at: :asc, id: :asc).page(params[:page]).per(THREAD_PER_PAGE)
    Message.unread_for_admin.where(user_id: @user.id).update_all(is_read: true)
  end

  # 回复 = 新建 admin 消息（管理员回复不做敏感词过滤，沿用旧行为）
  def reply
    @user = User.find(params[:user_id])
    content = params[:reply].to_s.strip
    if content.present?
      @user.messages.create!(sender: "admin", content: content)
      flash[:notice] = "回复成功"
    else
      flash[:alert] = "回复内容不能为空"
    end
    # 回复落在最新一页（正序分页的末页），避免多页会话跳回最老的第 1 页
    last_page = @user.messages.page(1).per(THREAD_PER_PAGE).total_pages
    redirect_to admin_message_thread_path(@user.id, page: last_page)
  end

  # 软删除单条消息（用户端显示隐藏占位）
  def destroy
    @msg = Message.find(params[:id])
    @msg.soft_destroy
    redirect_to admin_message_thread_path(@msg.user_id)
  end

  # 恢复软删除消息
  def restore
    @msg = Message.find(params[:id])
    @msg.restore
    redirect_to admin_message_thread_path(@msg.user_id)
  end
end
