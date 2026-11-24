module WindowWatch
  # 月批快照落库（契约 02 v0.3 §四）：全量校验收集所有错误 → 通过则事务内整包覆盖落库
  # 返回 [snapshot, errors]；errors 非空 = 422 全量拒绝，不落半包（幂等键 month）
  # 校验顺序：①头字段 ②tiers 逐股 ③stats 对账 ④universe 自洽 ⑤code 命中（防御性，纪要决议3）
  class SnapshotIngest
    TIERS = WindowWatchSnapshotStock::TIERS
    SUBTAGS = WindowWatchSnapshotStock::SUBTAGS
    MONTH_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/
    REQUIRED_STOCK_FIELDS = %w[symbol code name tier exchange hist prev_hist dif dea ratio sa_run].freeze
    REQUIRED_STATS_KEYS = %w[main_group_run3 main_group_run5 finance_count st_count bj_count].freeze

    def self.call(payload:, source_ip: nil)
      new(payload, source_ip).call
    end

    def initialize(payload, source_ip)
      @payload = deep_stringify(payload)
      @source_ip = source_ip
      @errors = []
    end

    def call
      rows = validate!
      return reject! if @errors.any?

      snapshot = persist!(rows)
      [snapshot, []]
    rescue ActiveRecord::ActiveRecordError => e
      # 校验通过但落库异常（含 ok 审计日志失败）：事务整体回滚，同样整包拒绝并留审计
      @errors << "落库异常：#{e.class}: #{e.message}"
      reject!
    end

    private

    def reject!
      WindowWatchIngestLog.create!(snapshot_month: @payload["month"].to_s.presence,
                                   snapshot_version: @payload["snapshot_version"].to_s.presence,
                                   source_ip: @source_ip, result: "rejected", error_messages: @errors.join("；"))
      [nil, @errors]
    end

    def validate!
      check_head!
      rows = check_tiers!
      check_stats!(rows)
      check_universe!(rows)
      check_stock_codes!(rows)
      rows
    end

    def check_head!
      %w[month snapshot_version caliber_version script_version].each do |key|
        @errors << "缺少 #{key}" if @payload[key].to_s.strip.empty?
      end
      @errors << "month 格式须为 YYYY-MM" if @payload["month"].to_s.present? && !@payload["month"].to_s.match?(MONTH_FORMAT)
      @errors << "disclaimer 不能为空" if @payload["disclaimer"].to_s.strip.empty?
      %w[data_snapshot universe stats].each do |key|
        @errors << "#{key} 必须为对象" unless @payload[key].is_a?(Hash)
      end
      @errors << "tiers 必须为对象" unless @payload["tiers"].is_a?(Hash)
    end

    def check_tiers!
      return [] unless @payload["tiers"].is_a?(Hash)
      tiers = @payload["tiers"]
      missing = TIERS.reject { |t| tiers[t].is_a?(Array) }
      @errors << "tiers 缺少数组键：#{missing.join('/')}" if missing.any?

      rows = []
      seen = {}
      tiers.slice(*TIERS).each do |tier, list|
        next unless list.is_a?(Array)
        list.each do |item|
          unless item.is_a?(Hash)
            @errors << "#{tier} 档存在非对象条目"
            next
          end
          row = deep_stringify(item).merge("_tier" => tier)
          symbol = row["symbol"].to_s
          if seen.key?(symbol)
            @errors << "symbol 重复：#{symbol}"
            next
          end
          seen[symbol] = true

          absent = REQUIRED_STOCK_FIELDS.reject { |f| row.key?(f) && !row[f].nil? }
          @errors << "#{symbol} 必填字段缺失：#{absent.join('/')}" if absent.any?
          @errors << "#{symbol} tier 非法：#{row['tier']}" if row["tier"].present? && !TIERS.include?(row["tier"])
          @errors << "#{symbol} tier=#{row['tier']} 与所在档数组键 #{tier} 不一致" if row["tier"].present? && TIERS.include?(row["tier"]) && row["tier"] != tier
          @errors << "#{symbol} subtag 非法：#{row['subtag']}" if row["subtag"].present? && !SUBTAGS.include?(row["subtag"])
          ex = row["exchange"].to_s.upcase
          @errors << "#{symbol} exchange 非法（tiers 内仅 SH/SZ）：#{row['exchange']}" unless ex.in?(%w[SH SZ])
          code_prefix = row["code"].to_s[0, 2].upcase
          @errors << "#{symbol} exchange=#{ex} 与 code 前缀=#{code_prefix} 不一致" if ex.in?(%w[SH SZ]) && ex != code_prefix
          rows << row
        end
      end
      rows
    end

    def check_stats!(rows)
      stats = @payload["stats"]
      return unless stats.is_a?(Hash)

      tc = stats["tier_counts"]
      unless tc.is_a?(Hash)
        @errors << "stats.tier_counts 必须为对象"
        tc = {}
      end
      TIERS.each do |t|
        v = tc[t]
        next if v.is_a?(Integer) && v >= 0
        @errors << "stats.tier_counts.#{t} 须为非负整数（无 null）"
      end
      REQUIRED_STATS_KEYS.each do |k|
        v = stats[k]
        @errors << "stats.#{k} 须为非负整数（无 null）" unless v.is_a?(Integer) && v >= 0
      end

      TIERS.each do |t|
        v = tc[t]
        actual = rows.count { |r| r["_tier"] == t }
        @errors << "tier_counts.#{t}=#{v} 与 tiers 实际条数 #{actual} 不一致" if v.is_a?(Integer) && v != actual
      end
      { "main_group_run3" => rows.count { |r| r["run3_asof"] == true },
        "main_group_run5" => rows.count { |r| r["run5_asof"] == true } }.each do |key, actual|
        v = stats[key]
        @errors << "#{key}=#{v} 与逐股行计数 #{actual} 不一致" if v.is_a?(Integer) && v != actual
      end
    end

    def check_universe!(rows)
      u = @payload["universe"]
      return unless u.is_a?(Hash)
      count = u["count"]
      ex = u["exchanges"]
      @errors << "universe.count 须为非负整数" unless count.is_a?(Integer) && count >= 0
      @errors << "universe.exchanges 必须为对象" unless ex.is_a?(Hash)
      return unless count.is_a?(Integer) && ex.is_a?(Hash)

      sum = ex.values.sum { |v| v.is_a?(Integer) ? v : 0 }
      @errors << "universe.exchanges 之和 #{sum} ≠ count #{count}" if sum != count
      %w[SH SZ].each do |e|
        actual = rows.count { |r| r["exchange"].to_s.upcase == e }
        @errors << "tiers 内 #{e} 只数 #{actual} 超过 universe.exchanges.#{e}=#{ex[e]}" if actual > ex[e].to_i
      end
      @errors << "tiers 内不应包含 BJ（北交所单列计数）" if rows.any? { |r| r["exchange"].to_s.upcase == "BJ" }
    end

    # 防御性校验（纪要决议3）：symbol/code 双向归一且互一致，并能在网站 stocks 表命中
    def check_stock_codes!(rows)
      return if rows.empty?
      unresolved = []
      codes = []
      rows.each do |r|
        n = normalized_stock_code(r)
        if n.nil?
          unresolved << "#{r['symbol']}(code=#{r['code']})"
        else
          codes << n
        end
      end
      @errors << "symbol/code 格式非法或互不一致：#{unresolved.join(',')}" if unresolved.any?
      hit = Stock.where(symbol: codes.uniq).pluck(:symbol).to_set
      misses = codes.uniq.reject { |s| hit.include?(s) }
      @errors << "以下 code 未命中网站股票库：#{misses.join(',')}" if misses.any?
    end

    # `600519.SH` ↔ `sh600519` 双向归一为站内 `SH600519`，两路不一致视为非法
    def normalized_stock_code(row)
      from_symbol = (m = row["symbol"].to_s.match(/\A(\d{6})\.(SH|SZ|BJ)\z/i)) && "#{m[2].upcase}#{m[1]}"
      from_code = (m = row["code"].to_s.match(/\A(SH|SZ|BJ)(\d{6})\z/i)) && "#{m[1].upcase}#{m[2]}"
      return nil if from_symbol.nil? || from_code.nil? || from_symbol != from_code
      from_symbol
    end

    def persist!(rows)
      now = Time.current
      ActiveRecord::Base.transaction do
        snapshot = WindowWatchSnapshot.find_or_initialize_by(month: @payload["month"])
        snapshot.assign_attributes(
          snapshot_version: @payload["snapshot_version"],
          caliber_version: @payload["caliber_version"],
          script_version: @payload["script_version"],
          generated_at: parse_time(@payload["generated_at"]),
          data_snapshot: @payload["data_snapshot"],
          universe: @payload["universe"],
          stats: @payload["stats"],
          disclaimer: @payload["disclaimer"]
        )
        snapshot.save!
        # 同月重推 = 整包覆盖：先清行再批量插入（事务内 all-or-nothing，V9）
        snapshot.stocks.delete_all
        WindowWatchSnapshotStock.insert_all!(rows.map { |r| row_attributes(r, snapshot.id, now) })
        # ok 审计日志同事务写入：日志失败=整包回滚，杜绝「已落库却报 422」的语义分裂
        WindowWatchIngestLog.create!(snapshot_month: snapshot.month, snapshot_version: snapshot.snapshot_version,
                                     counts: snapshot.stats, source_ip: @source_ip, result: "ok")
        snapshot
      end
    end

    def row_attributes(r, snapshot_id, now)
      {
        "window_watch_snapshot_id" => snapshot_id,
        "symbol" => r["symbol"], "code" => r["code"], "name" => r["name"],
        "industry" => r["industry"].to_s, "exchange" => r["exchange"].to_s.upcase,
        "tier" => r["tier"], "subtag" => r["subtag"].to_s,
        "finance" => r["finance"] == true, "st" => r["st"] == true,
        "run3_asof" => boolean_or_nil(r["run3_asof"]), "run5_asof" => boolean_or_nil(r["run5_asof"]),
        "roe" => r["roe"], "roe_band" => r["roe_band"].to_s,
        "hist" => r["hist"], "prev_hist" => r["prev_hist"],
        "dif" => r["dif"], "dea" => r["dea"], "ratio" => r["ratio"],
        "open_month" => r["open_month"], "months_since_open" => r["months_since_open"],
        "last_close_month" => r["last_close_month"], "sa_run" => r["sa_run"],
        "created_at" => now, "updated_at" => now
      }
    end

    def boolean_or_nil(v) = v == true || v == false ? v : nil
    def parse_time(str) = str.present? ? (Time.zone.parse(str.to_s) rescue nil) : nil

    def deep_stringify(obj)
      case obj
      when ActionController::Parameters then deep_stringify(obj.to_unsafe_h)
      when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array then obj.map { |v| deep_stringify(v) }
      else obj
      end
    end
  end
end
