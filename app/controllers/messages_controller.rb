class MessagesController < ApplicationController
  before_action :authenticate_user!

  PER_PAGE = 20

  # 会话页：当前用户与站长的消息流（正序、最新一页），进页即清悬浮按钮红点
  def show
    @messages = current_user.messages
                            .order(created_at: :desc, id: :desc)
                            .limit(PER_PAGE).reverse
    # 把站长回复全部标记已读（含被隐藏的消息，避免红点残留）
    current_user.messages.where(sender: "admin", is_read: false).update_all(is_read: true)
    oldest = @messages.first
    @earlier_cursor_at = oldest&.created_at
    @earlier_cursor_id = oldest&.id
    # 游标用 (created_at, id) 行值比较：回填存量数据 id 序与 created_at 序跨块不一致，单用 id 会漏历史
    @has_earlier = oldest.present? &&
                   current_user.messages
                             .where("(created_at, id) < (?, ?)", oldest.created_at, oldest.id)
                             .exists?
  end

  # 发送消息：敏感词拦截 → 追加气泡到流尾部 → 重置输入框
  def create
    content = params[:content].to_s.strip
    check_result = SensitiveService.check(content)
    unless check_result[:pass]
      return render turbo_stream: turbo_stream.replace(
        "message_flash",
        partial: "messages/flash",
        locals: { type: "alert", msg: check_result[:msg] }
      )
    end
    if content.empty?
      return render turbo_stream: turbo_stream.replace(
        "message_flash",
        partial: "messages/flash",
        locals: { type: "alert", msg: "留言内容不能为空" }
      )
    end

    @msg = current_user.messages.new(sender: "user", content: content)
    if @msg.save
      render turbo_stream: [
        turbo_stream.update("message_flash", ""),
        turbo_stream.remove("thread_empty_hint"),
        turbo_stream.append("message_thread",
          partial: "messages/bubble", locals: { msg: @msg }),
        turbo_stream.replace("message_form_area",
          partial: "messages/form")
      ]
    else
      render turbo_stream: turbo_stream.replace(
        "message_flash",
        partial: "messages/flash",
        locals: { type: "alert", msg: "留言发送失败，请重试" }
      )
    end
  end

  # 加载更早消息：按 (created_at, id) 复合游标取更早一页，prepend 到流头部并更新按钮状态
  def earlier
    before_at = Time.zone.parse(params[:before_at].to_s)
    before_id = params[:before_id].to_i
    return head(:bad_request) if before_at.blank? || before_id <= 0

    @earlier = current_user.messages
                           .where("(created_at, id) < (?, ?)", before_at, before_id)
                           .order(created_at: :desc, id: :desc)
                           .limit(PER_PAGE).reverse
    oldest = @earlier.first
    @new_cursor_at = oldest&.created_at
    @new_cursor_id = oldest&.id
    @has_earlier = oldest.present? &&
                   current_user.messages
                             .where("(created_at, id) < (?, ?)", oldest.created_at, oldest.id)
                             .exists?

    # 仅服务 turbo_stream；浏览器直接以 HTML 访问时回会话页，避免 MissingTemplate 500
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to messages_path }
    end
  end
end
