module Api
  module V1
    # 企业质量档案发布通道（契约见 .trae/documents/19/20/22 对齐系列）
    #   POST /api/v1/archive/profiles                 发布/覆盖（幂等键 code+period）
    #   POST /api/v1/archive/profiles/:id/withdraw    撤回（安全方向操作，立即下架）
    #   GET  /api/v1/archive/profiles                 查询列表（内容侧核对待审/已发）
    # 服务间 Bearer token 鉴权（HOLDLE_PUBLISH_TOKEN，与只读接口 token 分离）
    # 🔴 本接口任何路径都无法置 published——人工闸门只在 Admin 后台放行
    class ArchiveProfilesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :verify_service_token

      # 发布/覆盖
      def create
        stock = find_stock
        return render_error("stock not found", 404) unless stock

        period = params[:period].to_s.strip
        return render_error("period 格式须为 2025年报/2026中报/2026一季报/2026三季报", 422) unless period.match?(QualityProfile::PERIOD_FORMAT)
        unless QualityProfile.period_exists?(stock, period)
          return render_error("该股票不存在 #{period} 已披露期次，拒绝落库", 422)
        end

        return render_error("title 缺失", 422) if params[:title].to_s.strip.empty?
        return render_error("markdown 缺失", 422) if params[:markdown].to_s.strip.empty?

        meta = params[:meta].respond_to?(:to_unsafe_h) ? params[:meta].to_unsafe_h : params[:meta].to_h
        return render_error("meta.gate_passed 必须为布尔值", 422) unless [true, false].include?(meta["gate_passed"])
        return render_error("meta.ai_generated 必须为布尔值", 422) unless [true, false].include?(meta["ai_generated"])

        profile, warning = QualityProfilePublisher.call(
          stock: stock, period: period, title: params[:title].to_s.strip,
          markdown: params[:markdown].to_s, meta: meta
        )

        render json: {
          success: true,
          data: {
            profile_id: profile.id,
            code: display_code(stock),
            period: profile.period,
            status: profile.status,
            version_no: profile.current_version_no,
            warning: warning
          }
        }, status: profile.current_version_no == 1 && profile.published_at.nil? ? 201 : 200
      end

      # 撤回（published/superseded → withdrawn，前台立即仅引导页；幂等）
      def withdraw
        profile = QualityProfile.find_by(id: params[:id])
        return render_error("profile not found", 404) unless profile

        profile.withdraw!
        render json: { success: true, data: { profile_id: profile.id, status: profile.status } }
      end

      # 查询列表（code/period/status 均可选）
      def index
        scope = QualityProfile.order(updated_at: :desc).limit(100)
        if (stock = find_stock)
          scope = scope.where(stock_id: stock.id)
          scope = scope.where(period: params[:period].to_s.strip) if params[:period].present?
        end
        scope = scope.where(status: params[:status]) if params[:status].in?(QualityProfile::STATUSES)

        render json: {
          success: true,
          data: scope.map do |p|
            {
              profile_id: p.id, code: display_code(p.stock), period: p.period,
              title: p.title, status: p.status, current_version_no: p.current_version_no,
              published_version_no: p.published_version_no,
              published_at: p.published_at&.iso8601, updated_at: p.updated_at.iso8601
            }
          end
        }
      end

      private

      def verify_service_token
        expected = ENV["HOLDLE_PUBLISH_TOKEN"].to_s
        token = request.headers["Authorization"].to_s.remove("Bearer ")
        return if expected.present? && token == expected

        render_error("unauthorized", 401)
      end

      def render_error(message, code)
        render json: { success: false, error: message }, status: code
      end

      # code 归一化（与只读取数接口同规则）：后缀式/前缀式双向、大小写不敏感
      def find_stock
        raw = params[:code].to_s.strip
        return nil if raw.empty?

        if (m = raw.match(/\A(\d{6})\.(SH|SZ|BJ)\z/i))
          stock = Stock.find_by(symbol: "#{m[2].upcase}#{m[1]}")
        elsif (m = raw.match(/\A(SH|SZ|BJ)(\d{6})\z/i))
          stock = Stock.find_by(symbol: "#{m[1].upcase}#{m[2]}")
        end
        stock || Stock.find_by(symbol: raw)
      end

      def display_code(stock)
        if (m = stock.symbol.to_s.match(/\A(SH|SZ|BJ)(\d+)\z/))
          "#{m[2]}.#{m[1]}"
        else
          stock.symbol
        end
      end
    end
  end
end
