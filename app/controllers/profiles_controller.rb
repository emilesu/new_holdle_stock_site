class ProfilesController < ApplicationController
  # 企业质量档案前台详情（付费会员可见，可见性判定在服务端执行——对齐确认稿 §四）
  # 路径：/archive/SH603259（最新期） /archive/SH603259/2025A（指定期）
  # 后缀式 603259.SH / 小写 sh603259 自动 301 归一化；对外内容只取已发布版本快照
  def show
    raw = params[:symbol].to_s
    # Rails 会把末段点号后识别为 format（603259.SH → symbol=603259, format=SH），先拼回原始输入
    raw = "#{raw}.#{params[:format]}" if params[:format].in?(%w[SH SZ BJ sh sz bj])
    normalized = normalize_symbol(raw)
    if normalized != raw
      path = "/archive/#{normalized}"
      path += "/#{params[:period_code]}" if params[:period_code].present?
      return redirect_to(path, status: 301)
    end

    @stock = Stock.find_by(symbol: normalized)
    raise(ActiveRecord::RecordNotFound) unless @stock

    @latest = @stock.quality_profiles.readable.max_by(&:period_sort_key)
    @profile = resolve_profile
    @content = @profile&.visible_content

    # 无档案 / 撤回 / 未发布 → 引导页（免费可见，不触发会员墙）
    return unless @content

    # 🔴 会员墙：未登录先存回跳，无权限引导升级，正文绝不进响应
    unless user_signed_in?
      store_return_to_location(request.fullpath)
      return redirect_to(new_user_session_path, alert: "企业质量档案仅限会员阅读，请先登录")
    end
    return redirect_to(join_path, alert: "企业质量档案为付费会员权益，请升级会员后阅读") unless current_user.is_member?

    @history = @stock.quality_profiles.readable.where.not(id: @profile.id).to_a.sort_by(&:period_sort_key).reverse

    # 正文走档案专用管道（剥离首 H1 + 锚点注入 + 目录），与 Admin 预览同管道；会员墙通过后才渲染
    @body_html, @toc = MarkdownRenderer.render_profile(@content.markdown)
  end

  private

  # 后缀式 → 前缀式、小写 → 大写；其余原样大写返回
  def normalize_symbol(raw)
    if (m = raw.match(/\A(\d{6})\.(SH|SZ|BJ)\z/i))
      "#{m[2].upcase}#{m[1]}"
    else
      raw.upcase
    end
  end

  def resolve_profile
    return @latest if params[:period_code].blank?

    year = params[:period_code][0, 4]
    label = "#{year}#{QualityProfile::PERIOD_SHORT[params[:period_code][4..]]}"
    profile = @stock.quality_profiles.find_by(period: label)
    return profile if profile&.visible_content

    # 指定期不可读：withdrawn 条目交给引导页展示「已更新」提示，其余回落最新期
    @unavailable = profile if profile && profile.status != "superseded"
    @latest
  end
end
