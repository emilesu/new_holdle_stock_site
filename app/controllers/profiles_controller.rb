class ProfilesController < ApplicationController
  # 非会员预览兜底截断长度：无导语段或未遇到二级标题边界时，按段落边界取前 ~400 字
  PREVIEW_CHAR_LIMIT = 400
  # 🔴 会员数据关键词（金字塔分/行业名次等，与股票详情页「会员可见」门控口径一致）：
  #   预览正文、目录、标题三处统一按此剔除，防止发布管道把数值写进任意一处
  MEMBER_ONLY_PATTERN = /金字塔|名次|排名/

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

    # 管理员经 is_member? 恒为 true，会员墙一个判断覆盖两类人
    @is_member = user_signed_in? && current_user.is_member?

    if @is_member
      @history = @stock.quality_profiles.readable.where.not(id: @profile.id).to_a.sort_by(&:period_sort_key).reverse

      # 正文走档案专用管道（剥离首 H1 + 锚点注入 + 目录），与 Admin 预览同管道；会员墙通过后才渲染
      @body_html, @toc = MarkdownRenderer.render_profile(@content.markdown)
    else
      # 🔴 会员墙（服务端截断，对齐股票筛选页遮罩口径）：
      #   非会员/匿名只拿到「首段预览」渲染结果，完整正文绝不进响应（查看源码同样拿不到）；
      #   目录从全文标题行提取为纯文本（无锚点），仅作结构展示
      # 🔴 金字塔分/行业名次属会员数据，档案速览块常落在预览区，按 MEMBER_ONLY_PATTERN 剔除；
      #   标题与目录同口径过滤（标题命中则回退通用标题），三处口径必须一致
      preview = strip_member_only(preview_markdown(@content.markdown))
      @preview_html = MarkdownRenderer.render_profile(preview).first
      @outline = outline_from_markdown(@content.markdown)
                   .reject { |item| item[:text].match?(MEMBER_ONLY_PATTERN) }
      @display_title = @content.title.to_s.match?(MEMBER_ONLY_PATTERN) ?
                         "#{@stock.name} · 企业质量档案（#{@profile.period}）" : @content.title
    end
  end

  private

  # 预览源截断：取首个二级标题（##）前的导语段，代码围栏内的 ## 行不算边界；
  # 导语含 H1 以外的实际正文即用导语。
  # 🔴 未遇到 ## 边界（整篇无二级标题）或导语为空时，一律兜底取前 PREVIEW_CHAR_LIMIT 字——
  #   防止无标题稿把整篇正文当「导语」泄露给非会员；
  #   短文档（≤400 字）整篇可见属既定试读钩子策略（真实档案稿均为长文）
  def preview_markdown(text)
    intro = []
    in_code = false
    cut = false
    text.each_line do |line|
      if line.start_with?("```")
        in_code = !in_code
        intro << line
        next
      end
      if !in_code && line.match?(/\A##\s/)
        cut = true
        break
      end
      intro << line
    end
    result = close_open_fence(intro.join)
    return result if cut && result.sub(/\A#\s[^\n]*\n/, "").match?(/\S/)

    head = text[0, PREVIEW_CHAR_LIMIT]
    boundary = head.rindex("\n\n")
    close_open_fence(boundary && boundary > 80 ? text[0, boundary] : head)
  end

  # 兜底切片可能切进 ``` 代码围栏内部（围栏行为奇数个），回退到未闭合围栏起点，
  # 避免预览渲染出吞到文末的未闭合 <pre>
  def close_open_fence(slice)
    return slice if slice.lines.count { |l| l.start_with?("```") }.even?

    idx = slice.rindex("```")
    slice[0, idx].rstrip + "\n\n"
  end

  # 会员数据行级剔除；表格按「块」处理：块内任一行命中即整块剔除——
  # 横向表格的表头行（含「金字塔分」）被逐行剔除后，数据行「| 851 |」不含关键词会残留泄露数值
  def strip_member_only(text)
    lines = text.lines
    result = []
    i = 0
    while i < lines.size
      if lines[i].start_with?("|")
        j = i
        j += 1 while j < lines.size && lines[j].start_with?("|")
        block = lines[i...j]
        result.concat(block) unless block.any? { |l| l.match?(MEMBER_ONLY_PATTERN) }
        i = j
      else
        result << lines[i] unless lines[i].match?(MEMBER_ONLY_PATTERN)
        i += 1
      end
    end
    result.join
  end

  # 全文标题行 → [{ level:, text: }]（跳过代码围栏；仅二级/三级标题，与正文管道目录口径一致）
  def outline_from_markdown(text)
    outline = []
    in_code = false
    text.each_line do |line|
      if line.start_with?("```")
        in_code = !in_code
        next
      end
      next if in_code

      m = line.match(/\A(##|###)\s+(.+?)\s*\z/)
      outline << { level: m[1].length, text: m[2] } if m
    end
    outline
  end

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
