# B站数据API回调控制器
# 用于接收B站开放平台的OAuth授权回调和数据推送
class Bilibili::CallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token

  # B站回调入口
  # GET  - OAuth授权回调（用户授权后跳转）
  # POST - 数据推送回调（B站服务器推送数据）
  def create
    Rails.logger.info "[Bilibili] Callback received: #{request.request_method} from #{request.remote_ip}"
    Rails.logger.info "[Bilibili] Params: #{params.except(:controller, :action).to_s}"

    if request.post?
      # 数据推送回调处理
      handle_data_push
    else
      # OAuth授权回调处理
      handle_oauth_callback
    end
  end

  private

  def handle_oauth_callback
    code = params[:code]
    if code.present?
      Rails.logger.info "[Bilibili] OAuth code received: #{code}"
      render json: { status: "ok", message: "Authorization code received" }
    else
      render json: { status: "error", message: "Missing authorization code" }, status: :bad_request
    end
  end

  def handle_data_push
    render json: { status: "ok" }
  end
end
