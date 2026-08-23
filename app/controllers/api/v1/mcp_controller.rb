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
            l.question = params[:question].to_s.strip.presence
            l.tool_name = params[:tool_name].to_s.strip.presence
            l.round_id = params[:round_id].to_s.strip.presence
          end
        rescue ActiveRecord::RecordNotUnique
          UsageLog.find_by!(request_id: params[:request_id])
        rescue ActiveRecord::RecordInvalid
          return render json: { ok: false, error: "请求参数无效" }, status: 400
        end

        render json: { ok: true, plan: api_key.plan_code, remaining: api_key.quota_remaining, request_id: params[:request_id] }
      end

      # ③ 确认扣次（幂等，同一 request_id 只扣一次；90s 滑动窗口：同 key 连续 confirm ≤90s 合并同回合不扣费）
      def confirm
        log = UsageLog.find_by(request_id: params[:request_id])
        return render json: { ok: true, already_processed: true } if log&.status.in?(%w[confirmed merged])
        return render json: { ok: false, error: "request 不存在" }, status: 404 unless log
        return render json: { ok: false, error: "request 已释放" }, status: 400 if log.status == "released"

        # 扣次必须基于预占时绑定的 key（log.api_key），并校验请求 key 与之一致，避免扣错 key
        api_key = log.api_key
        return render json: { ok: false, error: "key 与预占不一致" }, status: 400 unless key_matches?(params[:api_key], api_key)

        # 窗口判断 + 扣次整体放进 with_lock：行锁串行化同一 key 的 confirm，
        # 既杜绝并发双扣（decrement_quota! 丢更新），也保证窗口判定不并发竞态
        result = ApiKey.transaction do
          api_key.with_lock do
            # 锁内重载 log 并二次校验终态：防并发同 request_id 双 confirm 时，
            # 后到者把先到者已 confirmed/merged 的记录误当 precheck 覆盖改写
            log.reload
            next { already_processed: true } if log.status.in?(%w[confirmed merged])
            next { released: true } if log.status == "released"

            # 回合判定：round_id 优先（MCP 侧同一次用户提问复用同一 round_id），90s 滑动窗口仅兜底旧 agent
            # last = 该 key 最近一条 confirmed/merged 记录（窗口参照，含 merged 不误拆长链）
            last = UsageLog.where(api_key_id: api_key.id)
                           .where(status: %w[confirmed merged])
                           .order(confirmed_at: :desc).first

            current_round_id = log.round_id.presence

            if current_round_id && last && last.round_id == current_round_id
              # ① 同 round_id → 同回合，合并不扣费（覆盖复盘长链：检索→跑数据→补充检索间隔可 >90s）
              log.update!(status: "merged", consumed: 0, confirmed_at: Time.current, round_id: current_round_id)
              { merged: true, remaining: api_key.quota_remaining, round_id: current_round_id }
            elsif current_round_id
              # ② 换了 round_id → 新回合正常扣费（即使 <90s，防连问白嫖）；round_id 用 precheck 透传值
              api_key.decrement_quota!
              api_key.touch(:last_used_at)
              log.update!(status: "confirmed", consumed: 1, confirmed_at: Time.current, round_id: current_round_id)
              { merged: false, remaining: api_key.quota_remaining, round_id: current_round_id }
            elsif last && (Time.current - last.confirmed_at) <= 90.seconds
              # ③ 未传 round_id（旧 agent）→ 90s 滑动窗口兜底合并，沿用 last.round_id
              log.update!(status: "merged", consumed: 0, confirmed_at: Time.current, round_id: last.round_id)
              { merged: true, remaining: api_key.quota_remaining, round_id: last.round_id }
            else
              # ④ 未传 round_id 且超 90s → 新回合，round_id 由 Rails 生成兜底
              round_id = SecureRandom.uuid
              api_key.decrement_quota!
              api_key.touch(:last_used_at)
              log.update!(status: "confirmed", consumed: 1, confirmed_at: Time.current, round_id: round_id)
              { merged: false, remaining: api_key.quota_remaining, round_id: round_id }
            end
          end
        end

        if result[:already_processed]
          render json: { ok: true, already_processed: true }
        elsif result[:released]
          render json: { ok: false, error: "request 已释放" }, status: 400
        elsif result[:merged]
          render json: { ok: true, consumed: 0, merged: true, remaining: result[:remaining], round_id: result[:round_id] }
        else
          render json: { ok: true, consumed: 1, remaining: result[:remaining], round_id: result[:round_id] }
        end
      end

      # ④ 释放预占（检索失败，不扣费；幂等）。confirmed/merged 为终态，不再改动
      def release
        log = UsageLog.find_by(request_id: params[:request_id])
        log.update!(status: "released") if log && !log.status.in?(%w[confirmed merged])
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
