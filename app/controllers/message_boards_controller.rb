class MessageBoardsController < ApplicationController
  before_action :authenticate_user!

  def create
    check_result = SensitiveService.check(params[:content])
    unless check_result[:pass]
      return render turbo_stream: turbo_stream.replace("modal_flash_result",
        partial: "message_boards/result",
        locals: { type: "alert", msg: check_result[:msg] })
    end

    @msg = current_user.message_boards.new(
      username: current_user.nickname.presence || current_user.email.split('@').first,
      email: current_user.email,
      content: params[:content]
    )
    if @msg.save
      render turbo_stream: [
        turbo_stream.replace("modal_flash_result",
          partial: "message_boards/result",
          locals: { type: "notice", msg: "留言提交成功，管理员会尽快回复" }),
        turbo_stream.replace("message_form_content",
          partial: "message_boards/form")
      ]
    else
      render turbo_stream: turbo_stream.replace("modal_flash_result",
        partial: "message_boards/result",
        locals: { type: "alert", msg: "留言提交失败，请重试" })
    end
  end

  def my
    @messages = MessageBoard.my_msg(current_user).order(created_at: :desc).page(params[:page]).per(10)
    render turbo_stream: turbo_stream.update("message_modal_content", partial: "message_boards/my_list")
  end
end