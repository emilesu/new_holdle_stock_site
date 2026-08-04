module DataSources
  # 同步 A股/港股上市日期（东方财富 F10 组织资料报表）
  # 增量策略：仅处理 listing_date 为空的股票，避免重复请求
  # 美股暂不支持（东方财富美股 F10 报表无上市日期字段），美股次新标签由"数据<5年"兜底
  class StockListingDateService
    # 市场 => 东方财富 F10 组织资料报表名
    REPORTS = {
      "CN" => "RPT_F10_ORG_BASICINFO",
      "HK" => "RPT_HKF10_INFO_ORGPROFILE"
    }.freeze

    # 请求间隔（秒），避免触发数据源限流
    REQUEST_INTERVAL = 0.3

    class << self
      def call(market: nil)
        Rails.logger.info "=" * 70
        Rails.logger.info "开始同步上市日期（东方财富 F10）"
        Rails.logger.info "=" * 70

        stats = { total: 0, updated: 0, skipped: 0, failed: 0 }
        markets = market.present? ? [market] : REPORTS.keys

        markets.each do |m|
          unless REPORTS.key?(m)
            Rails.logger.warn "市场 #{m} 暂不支持上市日期同步，跳过"
            next
          end

          stocks = Stock.where(market: m).where(listing_date: nil)
          stats[:total] += stocks.size
          Rails.logger.info "[#{m}] 待同步 #{stocks.size} 只"

          stocks.find_each do |stock|
            begin
              date = fetch_listing_date(REPORTS[m], secucode(stock))
              if date && date <= Date.current
                stock.update_column(:listing_date, date)
                stats[:updated] += 1
              else
                stats[:skipped] += 1
                Rails.logger.warn "上市日期缺失或异常（未来日期）跳过 #{stock.symbol}: #{date}" if date
              end
            rescue => e
              stats[:failed] += 1
              Rails.logger.error "同步上市日期失败 #{stock.symbol}: #{e.message}"
            ensure
              sleep REQUEST_INTERVAL
            end
          end
        end

        Rails.logger.info "统计结果：总条数 #{stats[:total]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"
        Rails.logger.info "上市日期同步完成"
        stats
      end

      private

      # 库内 symbol → 东方财富 SECUCODE 格式（如 SH600519 → 600519.SH，00700.HK → 00700.HK）
      def secucode(stock)
        if stock.market == "CN"
          code = stock.symbol.sub(/\A[A-Z]{2}/, "")
          suffix = stock.symbol[0, 2].upcase
          "#{code}.#{suffix}"
        else
          stock.symbol
        end
      end

      # 查询成功但接口无上市日期数据时返回 nil（计入 skipped）
      # 请求失败（超时/断连重试耗尽、非 2xx、解析失败等）抛异常，由 call 层计入 failed，避免统计失真
      def fetch_listing_date(report_name, secucode)
        data = EastmoneyDatacenter.fetch_data(
          report_name: report_name,
          columns: "SECUCODE,LISTING_DATE",
          filter: %((SECUCODE="#{secucode}")),
          page_size: 1,
          raise_on_failure: true
        )
        return nil unless data.present?

        listing = data.first&.dig("LISTING_DATE")
        listing.present? ? Date.parse(listing.to_s) : nil
      end
    end
  end
end
