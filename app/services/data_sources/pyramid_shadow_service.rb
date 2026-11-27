module DataSources
  # 金字塔影子打分服务（纯计算，不写库）
  #
  # 方案A = 方向一 + 方向二 + 方向四 + 方向三「杠杆质量调节」：
  #   - 新增净现比项（经营现金流/净利润，0-60分）
  #   - ROE 改近年加权（权重 1,1,2,3,3）+ 衰退折扣（近3年均值 < 全期均值×0.7 → ×0.8）
  #   - 毛利率扩容至 0-100 分（水平60 + 稳定40）
  #   - 无杠杆ROE/ROE 比值做杠杆质量调节（系数 1.0/0.9/0.8/0.7），取消 ROA 减半规则
  #   - 保留生产版「均值≥25% 且 max/min>4倍 → 450」波动规则
  #
  # 方案B = 方案A + 方向五合并设计：
  #   - ROE 拆为水平分（0-400，插值表按 400/550 等比压缩）+ 稳定分（0-150）
  #   - 移除 max/min>4倍 规则（稳定分已覆盖波动惩罚）
  #   - 衰退折扣与杠杆调节仅作用于水平分
  class PyramidShadowService
    # 与生产版一致的 ROE 插值档位（0-550 口径，方案B 按比例压缩到 400）
    ROE_STEPS = [[10, 300], [15, 350], [20, 400], [25, 450], [30, 500], [35, 550]].freeze
    # 近年加权权重（最早 → 最近）
    RECENCY_WEIGHTS = [1, 1, 2, 3, 3].freeze
    # 杠杆质量调节档位：[无杠杆ROE/ROE 下限, 系数]
    LEVERAGE_TIERS = [[0.85, 1.0], [0.70, 0.9], [0.55, 0.8]].freeze
    LEVERAGE_FLOOR_FACTOR = 0.7

    class << self
      # @param stock [Stock] 需已预加载 preloaded_* 财务数据（或接受逐股查询）
      # @return [Hash, nil] { plan_a:, plan_b: }；无财务数据返回 nil
      def call(stock)
        financial_years = stock.financial_years.select { |y| y.to_i >= Date.current.year - 5 }.sort.last(5)
        return nil if financial_years.empty?

        all_data = financial_years.map { |year| stock.get_financial_data_by_year(year) }.compact
        return nil if all_data.empty?

        { plan_a: score_plan_a(all_data), plan_b: score_plan_b(all_data) }
      end

      private

      # ─────────────────────────── 方案A ───────────────────────────

      def score_plan_a(all_data)
        score = 0
        score += roe_score_plan_a(all_data)
        score += roa_score(all_data)                    # 取消减半规则
        score += net_income_score(all_data)
        score += asset_turnover_score(all_data)
        score += gross_margin_score_expanded(all_data)  # 方向四：扩容
        score += growth_score(all_data.filter_map { |d| d[:net_income]&.to_f })
        score += growth_score(all_data.filter_map { |d| d[:operating_cash_flow]&.to_f })
        score += cash_ratio_score(all_data)
        score += net_cash_ratio_score(all_data)         # 方向一：新增
        score.clamp(0, 1000)
      end

      # ROE 得分（0-550）：近年加权 + 插值 + 4倍波动规则 + 衰退折扣 + 杠杆调节
      def roe_score_plan_a(all_data)
        roe_values = all_data.filter_map { |d| d[:roe]&.to_f }
        return 0 if roe_values.size < 3 || roe_values.any? { |v| v <= 0 }

        avg_roe = weighted_roe_avg(roe_values)
        score = interpolate_roe_score(avg_roe)

        # 保留生产版波动规则：均值≥25% 但最大值超最小值4倍 → 450
        if avg_roe >= 25
          max_roe = roe_values.max
          min_roe = roe_values.min
          score = 450 if min_roe > 0 && max_roe / min_roe > 4
        end

        score *= 0.8 if declining?(roe_values)
        score *= leverage_factor(all_data)
        score.round
      end

      # ─────────────────────────── 方案B ───────────────────────────

      def score_plan_b(all_data)
        roe = roe_score_plan_b(all_data)
        score = 0
        score += roe[:level] + roe[:stability]
        score += roa_score(all_data)
        score += net_income_score(all_data)
        score += asset_turnover_score(all_data)
        score += gross_margin_score_expanded(all_data)
        score += growth_score(all_data.filter_map { |d| d[:net_income]&.to_f })
        score += growth_score(all_data.filter_map { |d| d[:operating_cash_flow]&.to_f })
        score += cash_ratio_score(all_data)
        score += net_cash_ratio_score(all_data)
        score.clamp(0, 1000)
      end

      # ROE 拆分：水平分（0-400）+ 稳定分（0-150），移除4倍波动规则
      def roe_score_plan_b(all_data)
        roe_values = all_data.filter_map { |d| d[:roe]&.to_f }
        return { level: 0, stability: 0 } if roe_values.size < 3 || roe_values.any? { |v| v <= 0 }

        avg_roe = weighted_roe_avg(roe_values)
        level = interpolate_roe_score(avg_roe) * (400.0 / 550)  # 等比压缩到 400
        level *= 0.8 if declining?(roe_values)
        level *= leverage_factor(all_data)

        stability = if roe_values.all? { |v| v >= 15 } then 150
                    elsif roe_values.all? { |v| v >= 10 } then 100
                    else 40
                    end

        { level: level.round, stability: stability }
      end

      # ─────────────────────── 共用计分项 ───────────────────────

      # ROA（0-100）：与生产版同档位，但取消「ROE≥450 时减半」
      def roa_score(all_data)
        roa_values = all_data.filter_map { |d| d[:roa]&.to_f }
        return 0 if roa_values.size < 3

        avg_roa = roa_values.sum / roa_values.size.to_f
        case
        when avg_roa >= 15 then 100
        when avg_roa >= 11 then 80
        when avg_roa >= 7 then 50
        else 0
        end
      end

      # 净利润规模（0-200）：与生产版一致
      def net_income_score(all_data)
        ni_values = all_data.filter_map { |d| d[:net_income]&.to_f }
        return 0 if ni_values.size < 5

        avg_ni = ni_values.sum / ni_values.size.to_f
        case
        when avg_ni >= 1000_0000_0000 then 200
        when avg_ni >= 500_0000_0000 then 150
        when avg_ni >= 100_0000_0000 then 100
        when avg_ni > 0 then 50
        else 0
        end
      end

      # 资产周转率（0-50）：与生产版一致
      def asset_turnover_score(all_data)
        turnover_values = all_data.filter_map { |d| d[:asset_turnover_ratio]&.to_f }
        return 0 if turnover_values.size < 5

        avg_turnover = turnover_values.sum / turnover_values.size.to_f
        avg_turnover > 0.8 ? 50 : 0
      end

      # 方向四：毛利率扩容（0-100）= 水平分（0-60）+ 稳定分（0-40）
      def gross_margin_score_expanded(all_data)
        gm_values = all_data.filter_map { |d| d[:gross_margin]&.to_f }
        return 0 if gm_values.size < 5

        avg_gm = gm_values.sum / gm_values.size.to_f
        level = if avg_gm >= 50 then 60
                elsif avg_gm >= 40 then 45
                elsif avg_gm >= 30 then 30
                elsif avg_gm >= 20 then 15
                else 0
                end

        spread = gm_values.max - gm_values.min
        stability = if spread < 5 then 40
                    elsif spread < 10 then 20
                    else 0
                    end

        level + stability
      end

      # 增长分（-90~90）：与生产版规则完全一致，净利润增长与现金流增长共用
      def growth_score(values)
        return 0 if values.size < 5

        score = 0
        weights = [15, 20, 25, 30]

        [0, 1, 2, 3].each_with_index do |i, idx|
          next if i + 1 >= values.size
          old_value = values[i]
          new_value = values[i + 1]
          next if old_value == 0

          if old_value < 0 || new_value < 0
            score -= weights[idx] if old_value > 0 && new_value < 0
            next
          end

          if new_value > old_value
            growth_ratio = (new_value - old_value) / old_value.abs * 100
            if growth_ratio >= 20
              score += weights[idx] * 1.5
            elsif growth_ratio >= 5
              score += weights[idx]
            else
              score += weights[idx] * 0.5
            end
          else
            drop_ratio = (old_value - new_value) / old_value.abs * 100
            if drop_ratio > 15
              score -= weights[idx]
            elsif drop_ratio > 5
              score -= weights[idx] * 0.5
            end
          end
        end

        score.round.clamp(-90, 90)
      end

      # 现金占总资产比率（0-50）：与生产版一致
      def cash_ratio_score(all_data)
        cr_values = all_data.filter_map { |d| d[:cash_to_assets_ratio]&.to_f }
        return 0 if cr_values.size < 3

        roe_values = all_data.filter_map { |d| d[:roe]&.to_f }
        return 0 if roe_values.size < 3 || roe_values.any? { |v| v <= 0 }

        avg_cr = cr_values.sum / cr_values.size.to_f
        case
        when avg_cr >= 20 then 50
        when avg_cr >= 10 then 25
        else 0
        end
      end

      # 方向一：净现比（0-60）
      # 逐年 经营现金流/净利润（仅统计净利润>0 的年份），有效年份≥3 才计分
      def net_cash_ratio_score(all_data)
        ratios = all_data.filter_map do |d|
          ni = d[:net_income]
          ocf = d[:operating_cash_flow]
          next if ni.nil? || ocf.nil?
          ni = ni.to_f
          ocf.to_f / ni if ni > 0
        end
        return 0 if ratios.size < 3

        avg = ratios.sum / ratios.size.to_f
        if avg >= 1.0 then 60
        elsif avg >= 0.8 then 30
        else 0
        end
      end

      # ─────────────────────── ROE 增强因子 ───────────────────────

      # 近年加权平均（数据不足5年时取尾部权重）
      def weighted_roe_avg(roe_values)
        weights = RECENCY_WEIGHTS.last(roe_values.size)
        roe_values.zip(weights).sum { |v, w| v * w } / weights.sum.to_f
      end

      # 线性插值（与生产版档位一致，返回 0-550）
      def interpolate_roe_score(avg_roe)
        return 550 if avg_roe >= 35
        return 0 if avg_roe < 10

        (lo, lo_score), (hi, hi_score) = ROE_STEPS.each_cons(2).find do |(l, _), (h, _)|
          avg_roe >= l && avg_roe < h
        end
        lo_score + (avg_roe - lo) / (hi - lo) * (hi_score - lo_score)
      end

      # 方向二：衰退折扣 —— 近3年简单均值 < 全期简单均值×0.7 视为盈利能力系统性下滑
      # 数据仅3年时近3年即全期，不会触发
      def declining?(roe_values)
        return false if roe_values.size < 4

        recent_avg = roe_values.last(3).sum / 3.0
        full_avg = roe_values.sum / roe_values.size.to_f
        recent_avg < full_avg * 0.7
      end

      # 方向三：杠杆质量调节 —— 无杠杆ROE均值 / ROE均值
      # 比值越接近1说明回报越不依赖杠杆；无有效无杠杆数据（港股/金融股/缺失）不惩罚
      # 仅统计无杠杆ROE非空的年份（flag 1/2/3/5/6 在组装层已置 nil）
      def leverage_factor(all_data)
        pairs = all_data.filter_map do |d|
          u = d[:unlevered_roe]
          r = d[:roe]
          [u.to_f, r.to_f] if u.present? && r.present?
        end
        return 1.0 if pairs.size < 3

        avg_unlevered = pairs.sum { |u, _| u } / pairs.size.to_f
        avg_roe = pairs.sum { |_, r| r } / pairs.size.to_f
        return 1.0 if avg_roe <= 0

        ratio = avg_unlevered / avg_roe
        LEVERAGE_TIERS.each { |threshold, factor| return factor if ratio >= threshold }
        LEVERAGE_FLOOR_FACTOR
      end
    end
  end
end
