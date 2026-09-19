require "test_helper"

module DataSources
  module Fetchers
    # 期次判定与保留策略：确保年报与季报口径不混，且历史残留记录可被清理
    class PeriodTypeTest < ActiveSupport::TestCase
      test "CnFetcher: DATE_TYPE_CODE 判定 A 股期次，缺字段时按日期兜底" do
        fetcher = CnFetcher.new

        assert_equal "annual", fetcher.send(:cn_period_type, { "DATE_TYPE_CODE" => "001" }, Date.new(2025, 12, 31))
        assert_equal "h1", fetcher.send(:cn_period_type, { "DATE_TYPE_CODE" => "002" }, Date.new(2025, 6, 30))
        assert_equal "q1", fetcher.send(:cn_period_type, { "DATE_TYPE_CODE" => "003" }, Date.new(2025, 3, 31))
        assert_equal "q3", fetcher.send(:cn_period_type, { "DATE_TYPE_CODE" => "004" }, Date.new(2025, 9, 30))

        # 指标接口无 DATE_TYPE_CODE，按报告日期月日推导
        assert_equal "h1", fetcher.send(:cn_period_type, {}, Date.new(2025, 6, 30))
        assert_equal "annual", fetcher.send(:cn_period_type, {}, Date.new(2025, 12, 31))
      end

      test "UsFetcher: 累计季报按 Qn 的月数判定" do
        fetcher = UsFetcher.new

        assert_equal "annual", fetcher.send(:us_period_type, "2025/FY", "年报")
        assert_equal "h1", fetcher.send(:us_period_type, "2025/Q6", "累计季报")
        assert_equal "q3", fetcher.send(:us_period_type, "2025/Q9", "累计季报")
        assert_equal "q1", fetcher.send(:us_period_type, "2026/Q1", "单季报")
        # 其余单季报变体非累计口径，一律排除
        assert_nil fetcher.send(:us_period_type, "2025/Q2", "单季报")
        assert_nil fetcher.send(:us_period_type, "2025/Q4", "单季报")
        # 资产负债表用中文标准期次文本（Qn 不可按月数解析）
        assert_equal "q1", fetcher.send(:us_period_type, "2026/Q1", "一季报")
        assert_equal "h1", fetcher.send(:us_period_type, "2025/Q6", "中报")
        assert_equal "q3", fetcher.send(:us_period_type, "2025/Q9", "三季报")
      end

      test "HkFetcher: 现金流量汇总表 REPORT_TYPE 文本判定期次" do
        fetcher = HkFetcher.new

        assert_equal "annual", HkFetcher::REPORT_TYPE_MAP["年报"]
        assert_equal "h1", HkFetcher::REPORT_TYPE_MAP["中报"]
        assert_equal "q1", HkFetcher::REPORT_TYPE_MAP["一季报"]
        assert_equal "q3", HkFetcher::REPORT_TYPE_MAP["三季报"]
        assert_nil HkFetcher::REPORT_TYPE_MAP["未知"]
        # 备选源：DATE_TYPE_CODE → period_type
        assert_equal "q3", fetcher.send(:period_type_for_date, Date.new(2025, 9, 30))
      end

      test "retention_period_set: 年报保留近 20 年，季报保留近 16 期" do
        fetcher = CnFetcher.new
        entries = []
        (2000..2025).each { |y| entries << { report_date: Date.new(y, 12, 31), period_type: "annual" } }
        (2020..2025).each do |y|
          entries << { report_date: Date.new(y, 3, 31), period_type: "q1" }
          entries << { report_date: Date.new(y, 6, 30), period_type: "h1" }
          entries << { report_date: Date.new(y, 9, 30), period_type: "q3" }
        end

        allowed = fetcher.send(:retention_period_set, entries)
        annual_dates = allowed.select { |pt, _d| pt == "annual" }.map(&:last)
        quarter_dates = allowed.reject { |pt, _d| pt == "annual" }.map(&:last)

        assert_equal 20, annual_dates.size
        assert_equal Date.new(2006, 12, 31), annual_dates.min
        assert_equal 16, quarter_dates.size
        # 保留最近 16 期季报：2020~2025 共 18 期，最早两期被剔除
        assert_equal Date.new(2020, 9, 30), quarter_dates.min
        assert_equal Date.new(2025, 9, 30), quarter_dates.max
      end

      test "cleanup_stale_records: 剔除误标为年报的季报残留与超期记录" do
        stock = Stock.create!(
          symbol: "PERIOD_CLEAN", name: "Period Clean Stock", market: "CN",
          exchange: "SH", sector: "消费", status: "active"
        )
        # 误标：中报日期被标为 annual
        stale_report = FinancialReport.create!(
          stock: stock, report_date: Date.new(2025, 6, 30), market: "CN",
          report_type: "CN_ANNUAL", currency: "CNY", period_type: "annual"
        )
        IncomeStatement.create!(
          financial_report: stale_report, stock: stock, report_date: Date.new(2025, 6, 30),
          market: "CN", period_type: "annual", net_income: 100
        )
        # 超期：2010 年报不在近 20 年内
        old_report = FinancialReport.create!(
          stock: stock, report_date: Date.new(2010, 12, 31), market: "CN",
          report_type: "CN_ANNUAL", currency: "CNY", period_type: "annual"
        )
        FinancialIndicator.create!(
          financial_report: old_report, stock: stock, report_date: Date.new(2010, 12, 31),
          market: "CN", period_type: "annual", roe_avg: 10.0
        )
        # 有效：2025 年报
        keep_report = FinancialReport.create!(
          stock: stock, report_date: Date.new(2025, 12, 31), market: "CN",
          report_type: "CN_ANNUAL", currency: "CNY", period_type: "annual"
        )
        FinancialIndicator.create!(
          financial_report: keep_report, stock: stock, report_date: Date.new(2025, 12, 31),
          market: "CN", period_type: "annual", roe_avg: 20.0
        )

        periods = [
          { report_date: Date.new(2025, 12, 31), period_type: "annual" },
          { report_date: Date.new(2025, 6, 30), period_type: "h1" }
        ]
        CnFetcher.new.send(:cleanup_stale_records, stock, "CN", periods)

        assert_equal 0, IncomeStatement.where(stock_id: stock.id).count
        assert_equal [ Date.new(2025, 12, 31) ], FinancialIndicator.where(stock_id: stock.id).pluck(:report_date)
        assert_equal [ Date.new(2025, 12, 31) ], FinancialReport.where(stock_id: stock.id).pluck(:report_date)
      ensure
        FinancialIndicator.where(stock_id: stock&.id).delete_all
        IncomeStatement.where(stock_id: stock&.id).delete_all
        FinancialReport.where(stock_id: stock&.id).delete_all
        stock&.destroy!
      end

      test "cleanup_stale_records: 期次返回不完整时跳过清理，不误删有效记录" do
        stock = Stock.create!(
          symbol: "PERIOD_PARTIAL", name: "Period Partial Stock", market: "CN",
          exchange: "SH", sector: "消费", status: "active"
        )
        # 库里已有 2025 年报 + 2025 中报，均为有效数据
        [ [ Date.new(2025, 12, 31), "annual" ], [ Date.new(2025, 6, 30), "h1" ] ].each do |date, period_type|
          report = FinancialReport.create!(
            stock: stock, report_date: date, market: "CN",
            report_type: "CN_ANNUAL", currency: "CNY", period_type: period_type
          )
          FinancialIndicator.create!(
            financial_report: report, stock: stock, report_date: date,
            market: "CN", period_type: period_type, roe_avg: 10.0
          )
        end

        # 本次只返回了更早的中报（模拟接口返回不完整）
        removed = CnFetcher.new.send(
          :cleanup_stale_records, stock, "CN", [ { report_date: Date.new(2025, 6, 30), period_type: "h1" } ]
        )

        assert_equal 0, removed
        assert_equal 2, FinancialIndicator.where(stock_id: stock.id).count
      ensure
        FinancialIndicator.where(stock_id: stock&.id).delete_all
        FinancialReport.where(stock_id: stock&.id).delete_all
        stock&.destroy!
      end
    end
  end
end
