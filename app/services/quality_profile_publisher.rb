class QualityProfilePublisher
  # 档案发布/覆盖（幂等键 stock+period），供发布 API 调用。
  # 状态规则（服务端强制，API 无法置 published）：
  #   meta.gate_passed=true  → pending_review（进人工闸门队列）
  #   meta.gate_passed=false → draft（只允许存草稿）
  # pyramid_score 与 pyramid_calc_at 以库内值为权威同源回填（对齐确认稿 §二.1），
  # 内容侧传值仅作校验参考，不一致时返回 warning。
  # 返回 [profile, warning]
  def self.call(stock:, period:, title:, markdown:, meta:)
    meta = meta.to_h.transform_keys(&:to_s)
    warning = score_warning(meta, stock)
    meta["pyramid_score"] = stock.pyramid_total_score.to_i
    meta["pyramid_calc_at"] = stock.last_pyramid_calc_at&.in_time_zone&.to_date&.to_s

    status = meta["gate_passed"] == true ? "pending_review" : "draft"

    profile = ActiveRecord::Base.transaction do
      p = QualityProfile.find_or_initialize_by(stock: stock, period: period)
      # 撤回稿重新发布：必须清空对外指针，重新过人工闸门才能再次可见（withdrawn 永不自动复活）
      was_withdrawn = p.persisted? && p.status == "withdrawn"
      p.current_version_no = p.new_record? ? 1 : p.current_version_no + 1
      p.title = title.to_s
      p.markdown = markdown.to_s
      p.meta = meta
      p.status = status
      p.withdrawn_at = nil
      p.published_version_no = nil if was_withdrawn
      p.save!
      p.versions.create!(version_no: p.current_version_no, title: p.title,
                         markdown: p.markdown, meta: meta)
      p
    end
    [profile, warning]
  end

  # 传入分数与库内不一致 → 提示（不阻断，库内值优先）
  def self.score_warning(meta, stock)
    incoming = meta["pyramid_score"]
    return nil if incoming.nil?

    lib = stock.pyramid_total_score.to_i
    iv = incoming.to_i
    iv != lib ? "传入 pyramid_score=#{iv} 与库内 #{lib} 不一致，已按库内值回填" : nil
  end
end
