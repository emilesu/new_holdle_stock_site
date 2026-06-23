class Admin::MessageBoardsController < Admin::BaseController
  before_action :set_msg, only: [:reply, :mark_read, :destroy, :restore]

  def index
    scope = MessageBoard.all
    if params[:show_deleted] == "1"
      scope = scope.deleted
    else
      scope = scope.normal
    end
    @messages = scope.order(created_at: :desc).page(params[:page]).per(10)
  end

  def reply
    if @msg.update(reply_content: params[:reply], replied_at: Time.current, is_read: true)
      flash[:notice] = "回复成功"
    else
      flash[:alert] = "回复失败"
    end
    redirect_to admin_message_boards_path
  end

  def mark_read
    @msg.update(is_read: true)
    redirect_to admin_message_boards_path
  end

  def destroy
    @msg.soft_destroy
    redirect_to admin_message_boards_path
  end

  def restore
    @msg.restore
    redirect_to admin_message_boards_path
  end

  private
  def set_msg
    @msg = MessageBoard.find(params[:id])
  end
end