module Admin
  # 数据质量问题台账：异常列表与人工标记处理
  class DataQualityController < BaseController
    PER_PAGE = 30

    def index
      @data_type = StockDataSyncState::DATA_TYPES.include?(params[:data_type]) ? params[:data_type] : nil
      @severity = DataQualityIssue::SEVERITIES.include?(params[:severity]) ? params[:severity] : nil
      @show_resolved = params[:resolved].present?

      @open_counts = DataQualityIssue.open.group(:severity).count
      @open_total = @open_counts.values.sum

      scope = @show_resolved ? DataQualityIssue.resolved : DataQualityIssue.open
      scope = scope.of_type(@data_type) if @data_type
      scope = scope.by_severity(@severity) if @severity

      @page = params[:page].presence&.to_i || 1
      @page = 1 if @page < 1
      @total_count = scope.count
      @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
      @issues = scope.order(detected_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def resolve
      issue = DataQualityIssue.find(params[:id])
      issue.resolve!("manual")
      redirect_to admin_data_quality_path(data_type: params[:data_type], severity: params[:severity]),
                  notice: "已标记为处理完成：#{issue.stock&.symbol} #{DataQualityIssue.issue_type_name(issue.issue_type)}"
    end
  end
end
