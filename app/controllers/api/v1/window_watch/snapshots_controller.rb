module Api
  module V1
    module WindowWatch
      # 月批快照 ingest（契约 02 v0.3 §四）：DSH 月批推送，服务间 Bearer token 鉴权
      #   POST /api/v1/window_watch/snapshots
      # 鉴权 token 独立发放（HOLDLE_WINDOW_TOKEN，与档案发布 token 分离），fail-closed
      # 校验与幂等落库全部在 WindowWatch::SnapshotIngest，本控制器只做鉴权与响应
      class SnapshotsController < ApplicationController
        skip_before_action :verify_authenticity_token
        before_action :verify_service_token

        def create
          snapshot, errors = ::WindowWatch::SnapshotIngest.call(payload: params, source_ip: request.remote_ip)
          if snapshot
            render json: { status: "ok", month: snapshot.month, counts: snapshot.stats["tier_counts"] }, status: 201
          else
            render json: { status: "rejected", errors: errors }, status: 422
          end
        end

        private

        def verify_service_token
          expected = ENV["HOLDLE_WINDOW_TOKEN"].to_s
          token = request.headers["Authorization"].to_s.remove("Bearer ")
          return if expected.present? && token == expected

          render json: { status: "unauthorized", error: "unauthorized" }, status: 401
        end
      end
    end
  end
end
