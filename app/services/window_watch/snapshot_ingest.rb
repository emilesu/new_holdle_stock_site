module WindowWatch
  # 月批快照落库（契约 02 v0.3 §四；v0.8 多市场承载）：全量校验收集所有错误 → 通过则事务内整包覆盖落库
  # 返回 [snapshot, errors]；errors 非空 = 422 全量拒绝，不落半包（幂等键 (market, month)，每 POST=单市场×单月一包）
  # 校验顺序：①头字段（含 universe.market 枚举）②tiers 逐股（CN/US 分支）③stats 对账 ④universe 自洽 ⑤code 命中（防御性，纪要决议3）
  # CN 侧校验逻辑 v0.8 零改动；US 细则见契约草案 §3.1/§四
  class SnapshotIngest
    TIERS = WindowWatchSnapshotStock::TIERS
    IN_POSITION = WindowWatchSnapshotStock::IN_POSITION
    ALL_TIERS = WindowWatchSnapshotStock::ALL_TIERS
    SUBTAGS = WindowWatchSnapshotStock::SUBTAGS
    MONTH_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/
    MARKETS = WindowWatchSnapshot::MARKETS
    # US code = Yahoo 底座码（大写，含 BRK.A 类带点码；站内 stocks.symbol 同值直存）
    US_CODE_FORMAT = /\A[A-Z][A-Z0-9.\-]{0,9}\z/
    REQUIRED_STOCK_FIELDS = %w[symbol code name tier exchange hist prev_hist dif dea ratio sa_run].freeze
    # 契约 v0.7：bj_count 键退役（北交所纳入所有档/桶，tiers 直接含 BJ 行）
    REQUIRED_STATS_KEYS = %w[in_position_count].freeze
    # 契约 v0.4.0 §四：快照不得携带任何财务字段（财务指标权威源=Trae 财务库，页面侧 join）
    FORBIDDEN_ROW_FIELDS = %w[run3_asof run5_asof roe roe_band finance st].freeze
    FORBIDDEN_STATS_KEYS = %w[main_group_run3 main_group_run5 finance_count st_count].freeze

    def self.call(payload:, source_ip: nil)
      new(payload, source_ip).call
    end

    def initialize(payload, source_ip)
      @payload = deep_stringify(payload)
      @source_ip = source_ip
      @errors = []
      # market 权威源=universe.market（契约 v0.8）；非法值 check_head! 报错后校验链即止（validate! 评审修复1）
      u = @payload["universe"]
      @market = u.is_a?(Hash) ? u["market"].to_s.upcase : ""
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
                                   market: @market.presence,
                                   source_ip: @source_ip, result: "rejected", error_messages: @errors.join("；"))
      [nil, @errors]
    end

    def validate!
      check_head!
      # market 非法时只报头错误即止——不再按 CN 分支叠加逐股/命中噪音（422 清单可读性，评审修复1）
      return [] unless @market.in?(MARKETS)
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
      # 契约 v0.8：market 枚举（universe.market 唯一权威源）
      @errors << "universe.market 非法（仅 CN/US）：#{@market.presence || "缺失"}" unless @market.in?(MARKETS)
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
      # v1.2：IN_POSITION 可选键（缺失=按 v1.1 处理，④区块降级为仅计数提示）
      if tiers.key?(IN_POSITION) && !tiers[IN_POSITION].is_a?(Array)
        @errors << "tiers.#{IN_POSITION} 须为数组（可选键，v1.2）"
      end

      rows = []
      seen = {}
      tiers.slice(*ALL_TIERS).each do |tier, list|
        next unless list.is_a?(Array)
        list.each do |item|
          unless item.is_a?(Hash)
            @errors << "#{tier} 档存在非对象条目"
            next
          end
          row = deep_stringify(item).merge("_tier" => tier)
          symbol = row["symbol"].to_s
          # seen 跨五键全局去重 = IN_POSITION 与四档互斥校验（契约 v0.5 §1.1）
          if seen.key?(symbol)
            @errors << "symbol 重复：#{symbol}"
            next
          end
          seen[symbol] = true

          absent = REQUIRED_STOCK_FIELDS.reject { |f| row.key?(f) && !row[f].nil? }
          @errors << "#{symbol} 必填字段缺失：#{absent.join('/')}" if absent.any?
          carried = FORBIDDEN_ROW_FIELDS.select { |f| row.key?(f) }
          @errors << "#{symbol} 不得携带财务字段：#{carried.join('/')}（v0.4.0 起财务指标移出快照）" if carried.any?
          @errors << "#{symbol} tier 非法：#{row['tier']}" if row["tier"].present? && !ALL_TIERS.include?(row["tier"])
          @errors << "#{symbol} tier=#{row['tier']} 与所在档数组键 #{tier} 不一致" if row["tier"].present? && ALL_TIERS.include?(row["tier"]) && row["tier"] != tier
          ex = row["exchange"].to_s.upcase
          if @market == "US"
            # 契约 v0.8 §3.1：US 包 exchange 恒 US；symbol == code + ".US" 整串拼接（非 endsWith，BRK.A.US 双点天然消歧）
            @errors << "#{symbol} exchange 非法（US 包恒 US）：#{row['exchange']}" unless ex == "US"
            code = row["code"].to_s
            @errors << "#{symbol} code 格式非法（须为大写 Yahoo 码）：#{code}" unless code.match?(US_CODE_FORMAT)
            @errors << "#{symbol} symbol 须为 code+\".US\" 整串拼接（code=#{code}）" unless symbol == "#{code}.US"
          else
            # 契约 v0.7：exchange 枚举扩 BJ（北交所与沪深同权进 tiers）
            @errors << "#{symbol} exchange 非法（tiers 内仅 SH/SZ/BJ）：#{row['exchange']}" unless ex.in?(%w[SH SZ BJ])
            code_prefix = row["code"].to_s[0, 2].upcase
            @errors << "#{symbol} exchange=#{ex} 与 code 前缀=#{code_prefix} 不一致" if ex.in?(%w[SH SZ BJ]) && ex != code_prefix
          end

          if tier == IN_POSITION
            # 契约 v0.5 §1.2：subtag 恒空；entry_month 仅验格式（可晚于判定月，口径②）；months_in_position int≥1（DSH 算好，页面如实展示）
            @errors << "#{symbol} IN_POSITION 行 subtag 须为空" if row["subtag"].present?
            em = row["entry_month"].to_s
            @errors << "#{symbol} entry_month 缺失或格式非 YYYY-MM：#{em}" unless em.match?(MONTH_FORMAT)
            mip = row["months_in_position"]
            @errors << "#{symbol} months_in_position 须为 ≥1 整数：#{mip.inspect}" unless mip.is_a?(Integer) && mip >= 1
          else
            @errors << "#{symbol} subtag 非法：#{row['subtag']}" if row["subtag"].present? && !SUBTAGS.include?(row["subtag"])
          end
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
      # v1.2 对账：tiers 下发 IN_POSITION 时，in_position_count 必须等于其行数（§二.3）
      if @payload["tiers"].is_a?(Hash) && @payload["tiers"][IN_POSITION].is_a?(Array)
        v = stats["in_position_count"]
        actual = rows.count { |r| r["_tier"] == IN_POSITION }
        @errors << "stats.in_position_count=#{v} 与 tiers.#{IN_POSITION} 实际条数 #{actual} 不一致" if v.is_a?(Integer) && v != actual
      end
      carried = FORBIDDEN_STATS_KEYS.select { |k| stats.key?(k) }
      @errors << "stats 不得携带财务统计键：#{carried.join('/')}（v0.4.0 起财务指标移出快照）" if carried.any?
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
      if @market == "US"
        # 契约 v0.8 §四：US 包 exchanges 单键 {"US": N}；N=universe.count（sum 校验已覆盖）=全池只数
        # 键名精确匹配大写 "US"（与 CN 分支 SH/SZ/BJ 既有约定一致）；非单键时报准确错误并跳过上限校验，
        # 避免小写键落入上限校验产出误导性的「超过 universe.exchanges.US=0」（评审修复3）
        foreign = ex.keys - ["US"]
        if foreign.any?
          @errors << "US 包 universe.exchanges 仅允许 US 单键，发现：#{foreign.join('/')}"
        else
          actual = rows.count { |r| r["exchange"].to_s.upcase == "US" }
          @errors << "tiers 内 US 只数 #{actual} 超过 universe.exchanges.US=#{ex["US"]}" if actual > ex["US"].to_i
        end
      else
        # 契约 v0.7：BJ 与沪深同权进 tiers，只数上限校验一并覆盖；原「tiers 不含 BJ」硬闸删除
        %w[SH SZ BJ].each do |e|
          actual = rows.count { |r| r["exchange"].to_s.upcase == e }
          @errors << "tiers 内 #{e} 只数 #{actual} 超过 universe.exchanges.#{e}=#{ex[e]}" if actual > ex[e].to_i
        end
      end
    end

    # 防御性校验（纪要决议3）：symbol/code 双向归一且互一致，并能在网站 stocks 表命中（market 同域限定，契约 v0.8）
    def check_stock_codes!(rows)
      return if rows.empty?
      unresolved = []
      codes = []
      rows.each do |r|
        n = @market == "US" ? normalized_us_code(r) : normalized_stock_code(r)
        if n.nil?
          unresolved << "#{r['symbol']}(code=#{r['code']})"
        else
          codes << n
        end
      end
      @errors << "symbol/code 格式非法或互不一致：#{unresolved.join(',')}" if unresolved.any?
      # US 命中双向归一（契约 v0.8 归一化认领项，2026-11-26）：库内历史斜杠形态（BRK/A，Nasdaq screener 源）
      # 与 Yahoo 点形态（BRK.A）互认命中——两侧统一 tr 为点形态后比对；库内已由迁移规范为点，此处防数据漂移
      candidates = @market == "US" ? (codes + codes.map { |c| c.tr(".", "/") }).uniq : codes.uniq
      hit = Stock.where(market: @market, symbol: candidates).pluck(:symbol)
      hit = hit.map { |s| s.tr("/", ".") }.to_set if @market == "US"
      hit = hit.to_set unless hit.is_a?(Set)
      misses = codes.uniq.reject { |s| hit.include?(@market == "US" ? s.tr("/", ".") : s) }
      @errors << "以下 code 未命中网站股票库：#{misses.join(',')}" if misses.any?
    end

    # `600519.SH` ↔ `sh600519` 双向归一为站内 `SH600519`，两路不一致视为非法
    def normalized_stock_code(row)
      from_symbol = (m = row["symbol"].to_s.match(/\A(\d{6})\.(SH|SZ|BJ)\z/i)) && "#{m[2].upcase}#{m[1]}"
      from_code = (m = row["code"].to_s.match(/\A(SH|SZ|BJ)(\d{6})\z/i)) && "#{m[1].upcase}#{m[2]}"
      return nil if from_symbol.nil? || from_code.nil? || from_symbol != from_code
      from_symbol
    end

    # US（契约 v0.8 §3.1）：站内 stocks.symbol=Yahoo 裸码（AAPL/BRK.B，NasdaqStockListService 现约定）
    # =快照 code 原值；symbol==code+".US" 拼接一致才返回，命中校验按 market=US 限定
    def normalized_us_code(row)
      code = row["code"].to_s
      return nil unless code.match?(US_CODE_FORMAT) && row["symbol"].to_s == "#{code}.US"
      code
    end

    def persist!(rows)
      now = Time.current
      ActiveRecord::Base.transaction do
        # 契约 v0.8：幂等键 (market, month)——CN/US 同月各存一包，互不覆盖；同键重推=整包覆盖
        snapshot = WindowWatchSnapshot.find_or_initialize_by(month: @payload["month"], market: @market)
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
                                     market: snapshot.market, counts: snapshot.stats, source_ip: @source_ip, result: "ok")
        snapshot
      end
    end

    def row_attributes(r, snapshot_id, now)
      {
        "window_watch_snapshot_id" => snapshot_id,
        "symbol" => r["symbol"], "code" => r["code"].to_s.downcase, "name" => r["name"],
        "industry" => r["industry"].to_s, "exchange" => r["exchange"].to_s.upcase,
        "tier" => r["tier"], "subtag" => r["subtag"].to_s,
        "hist" => r["hist"], "prev_hist" => r["prev_hist"],
        "dif" => r["dif"], "dea" => r["dea"], "ratio" => r["ratio"],
        "open_month" => r["open_month"], "months_since_open" => r["months_since_open"],
        "last_close_month" => r["last_close_month"], "sa_run" => r["sa_run"],
        "entry_month" => r["entry_month"], "months_in_position" => r["months_in_position"],
        "created_at" => now, "updated_at" => now
      }
    end

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
