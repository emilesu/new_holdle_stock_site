module Api
  module V1
    # T7 计费后台：MCP 服务三步扣次接口（接口契约硬约束，见 03_T7计费后台设计_v0.2.md）
    #   precheck → 校验 key + 预占（记日志）→ MCP 检索 → confirm（幂等扣次）/ release（释放）
    class McpController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :verify_service_token

      # ① 预检 + 预占
      def precheck
        return render json: { ok: false, error: "request_id 缺失" }, status: 400 if params[:request_id].blank?

        api_key = find_by_plain_key(params[:api_key])
        return render json: { ok: false, error: "key 已停用" }, status: 403 if api_key&.status == "disabled"
        return render json: { ok: false, error: "key 无效" }, status: 401 unless api_key&.active?
        return render json: { ok: false, error: "次数已用完，请充值" }, status: 402 if !api_key.unlimited? && api_key.quota_remaining <= 0

        # 预占：记录 usage_log（request_id 幂等；并发下唯一索引兜底，冲突则取已存在记录）
        begin
          UsageLog.find_or_create_by!(request_id: params[:request_id]) do |l|
            l.api_key = api_key
            l.user = api_key.user
            l.status = "precheck"
            l.ip = request.remote_ip
          end
        rescue ActiveRecord::RecordNotUnique
          UsageLog.find_by!(request_id: params[:request_id])
        rescue ActiveRecord::RecordInvalid
          return render json: { ok: false, error: "request_id 无效" }, status: 400
        end

        render json: { ok: true, plan: api_key.plan_code, remaining: api_key.quota_remaining, request_id: params[:request_id] }
      end

      # ③ 确认扣次（幂等，同一 request_id 只扣一次）
      def confirm
        log = UsageLog.find_by(request_id: params[:request_id])
        return render json: { ok: true, already_processed: true } if log&.status == "confirmed"
        return render json: { ok: false, error: "request 不存在" }, status: 404 unless log
        return render json: { ok: false, error: "request 已释放" }, status: 400 if log.status == "released"

        # 扣次必须基于预占时绑定的 key（log.api_key），并校验请求 key 与之一致，避免扣错 key
        api_key = log.api_key
        return render json: { ok: false, error: "key 与预占不一致" }, status: 400 unless key_matches?(params[:api_key], api_key)

        ApiKey.transaction do
          api_key.decrement_quota!
          api_key.touch(:last_used_at)
          log.update!(status: "confirmed", consumed: 1, confirmed_at: Time.current)
        end

        render json: { ok: true, consumed: 1, remaining: api_key.quota_remaining }
      end

      # ④ 释放预占（检索失败，不扣费；幂等）
      def release
        UsageLog.find_by(request_id: params[:request_id])&.update!(status: "released")
        render json: { ok: true, released: true }
      end

      private

      def find_by_plain_key(plain)
        return nil if plain.blank?
        ApiKey.find_by(key_hash: Digest::SHA256.hexdigest(plain))
      end

      # 校验请求中的明文 key 是否就是预占时绑定的 key
      def key_matches?(plain, api_key)
        plain.present? && Digest::SHA256.hexdigest(plain) == api_key.key_hash
      end

      def verify_service_token
        token = request.headers["Authorization"].to_s.remove("Bearer ")
        return if token.present? && token == ENV["MCP_SERVICE_TOKEN"]

        render json: { ok: false, error: "unauthorized" }, status: 401
      end
    end
  end
end
