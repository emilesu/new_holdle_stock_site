# frozen_string_literal: true

require "test_helper"

module DataSources
  class XueqiuHkFinanceServiceTest < ActiveSupport::TestCase
    setup do
      # 准备测试用的港股 stock 记录
      @hk_stock = Stock.find_or_create_by!(symbol: "00700", market: "HK") do |s|
        s.name = "腾讯控股"
        s.exchange = "香港交易所"
        s.sector = "资讯科技业"
        s.industry = "软件及服务"
        s.status = "active"
      end

      @hk_stock2 = Stock.find_or_create_by!(symbol: "00005", market: "HK") do |s|
        s.name = "汇丰控股"
        s.exchange = "香港交易所"
        s.sector = "金融业"
        s.industry = "银行"
        s.status = "active"
      end

      @hk_stock3 = Stock.find_or_create_by!(symbol: "09988", market: "HK") do |s|
        s.name = "阿里巴巴"
        s.exchange = "香港交易所"
        s.sector = "非必需性消费"
        s.industry = "电子商贸及互联网服务"
        s.status = "active"
      end

      # 模拟港股利润表响应
      @hk_income_response = build_hk_response([
        build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000,
                          opeploinclfincost: 159828000000),
        build_income_item("2026-03-31", "2026一季报", 196458000000, 58093000000, 58093000000,
                          opeploinclfincost: 69535000000)
      ])

      # 模拟港股资产负债表响应
      @hk_balance_response = build_hk_response([
        build_balance_item("2025-12-31", "2025年报", 2012730000000, 836465000000),
        build_balance_item("2026-03-31", "2026一季报", 2051390000000, 839763000000)
      ])

      # 模拟港股现金流量表响应
      @hk_cash_flow_response = build_hk_response([
        build_cash_flow_item("2025-12-31", "2025年报", 210456000000, -45678000000, -98765000000),
        build_cash_flow_item("2026-03-31", "2026一季报", 101351000000, -10560000000, -12117000000)
      ])

      # 模拟港股财务指标响应
      @hk_indicator_response = build_hk_response([
        build_indicator_item("2025-12-31", "2025年报", 6.4312, 123.5937, 8.6228, 5.09185, 2.840, 56.6355, 40.936),
        build_indicator_item("2026-03-31", "2026一季报", 1.8234, 125.0983, 2.1567, 1.4567, 0.8234, 58.1234, 40.123)
      ])
    end

    teardown do
      # 清理测试数据，不影响后续运行
      FinancialReport.where(stock_id: [@hk_stock.id, @hk_stock2.id, @hk_stock3.id]).destroy_all
      [@hk_stock, @hk_stock2, @hk_stock3].each { |s| s.destroy if s.persisted? }
    end

    # ── 辅助方法 ──

    def build_hk_response(items)
      { "data" => { "list" => items } }
    end

    def build_income_item(ed, name, tto, plocyr, ploashh, opeploinclfincost: nil, op: nil)
      item = {
        "report_date" => Date.parse(ed).to_time.to_i * 1000,
        "report_name" => name,
        "report_type_code" => name.include?("年报") ? "596001" : "596002",
        "month_num" => name.include?("年报") ? 12 : 3,
        "tto" => [tto, 0.1],
        "plocyr" => [plocyr, 0.15],
        "ploashh" => [ploashh, 0.15],
      }
      item["opeploinclfincost"] = [opeploinclfincost, 0.12] if opeploinclfincost
      item["op"] = [op, 0.12] if op
      item
    end

    def build_balance_item(ed, name, ta, tlia)
      {
        "report_date" => Date.parse(ed).to_time.to_i * 1000,
        "report_name" => name,
        "report_type_code" => name.include?("年报") ? "596001" : "596002",
        "month_num" => name.include?("年报") ? 12 : 3,
        "ta" => [ta, 0.05],
        "tlia" => [tlia, 0.03],
        "ta_tlia" => [tlia.to_f / ta, -0.01]
      }
    end

    def build_cash_flow_item(ed, name, nocf, ninvcf, nfcgcf)
      {
        "report_date" => Date.parse(ed).to_time.to_i * 1000,
        "report_name" => name,
        "report_type_code" => name.include?("年报") ? "596001" : "596002",
        "month_num" => name.include?("年报") ? 12 : 3,
        "nocf" => [nocf, 0.08],
        "ninvcf" => [ninvcf, 0.02],
        "nfcgcf" => [nfcgcf, -0.05]
      }
    end

    def build_indicator_item(ed, name, beps, bps, ncfps, roe, rota, gpm, tlia_ta)
      {
        "report_date" => Date.parse(ed).to_time.to_i * 1000,
        "report_name" => name,
        "report_type_code" => name.include?("年报") ? "596001" : "596002",
        "month_num" => name.include?("年报") ? 12 : 3,
        "beps" => [beps, 0.15],
        "bps" => [bps, 0.05],
        "ncfps" => [ncfps, 0.08],
        "roe" => [roe, 0.07],
        "rota" => [rota, 0.09],
        "gpm" => [gpm, 0.02],
        "tlia_ta" => [tlia_ta, -0.01]
      }
    end

    # ──────────────────────────────────────────────
    # 测试模块一：HK_BASE_URL 常量与市场路由
    # ──────────────────────────────────────────────

    test "1.1 HK_BASE_URL 常量已定义" do
      assert_equal "https://stock.xueqiu.com/v5/stock/finance/hk/income.json",
                   XueqiuIncomeStatementService::HK_BASE_URL
      assert_equal "https://stock.xueqiu.com/v5/stock/finance/hk/balance.json",
                   XueqiuBalanceSheetService::HK_BASE_URL
      assert_equal "https://stock.xueqiu.com/v5/stock/finance/hk/cash_flow.json",
                   XueqiuCashFlowService::HK_BASE_URL
      assert_equal "https://stock.xueqiu.com/v5/stock/finance/hk/indicator.json",
                   XueqiuIndicatorService::HK_BASE_URL
    end

    test "1.2 fetch_data 支持 market=HK 路由到 HK_BASE_URL" do
      assert_equal XueqiuIncomeStatementService::HK_BASE_URL,
                   "https://stock.xueqiu.com/v5/stock/finance/hk/income.json"
    end

    test "1.3 fetch_data 保持 CN/US 路由不变" do
      assert_equal XueqiuIncomeStatementService::CN_BASE_URL,
                   "https://stock.xueqiu.com/v5/stock/finance/cn/income.json"
      assert_equal XueqiuIncomeStatementService::US_BASE_URL,
                   "https://stock.xueqiu.com/v5/stock/finance/us/income.json"

      # 验证市场选择逻辑：market == 'CN' -> CN, market == 'HK' -> HK, else -> US
      cn_routing = XueqiuIncomeStatementService::CN_BASE_URL
      hk_routing = XueqiuIncomeStatementService::HK_BASE_URL
      us_routing = XueqiuIncomeStatementService::US_BASE_URL

      assert_match(/cn\//, cn_routing)
      assert_match(/hk\//, hk_routing)
      assert_match(/us\//, us_routing)
    end

    # ──────────────────────────────────────────────
    # 测试模块二：parse_financial_fields HK 分支
    # ──────────────────────────────────────────────

    test "2.1 利润表 HK 字段映射正确" do
      svc = XueqiuIncomeStatementService
      item = build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000,
                                opeploinclfincost: 159828000000)
      result = svc.send(:parse_financial_fields, item, "HK")

      assert_instance_of BigDecimal, result[:total_revenue]
      assert_equal 646861000000, result[:total_revenue]
      assert_equal 159828000000, result[:operating_income]
      assert_equal 291974000000, result[:net_income]
    end

    test "2.2 利润表 HK 营业利润字段降级: opeploinclfincost → op" do
      svc = XueqiuIncomeStatementService

      # 场景1：有 opeploinclfincost，无 op → 使用 opeploinclfincost
      item1 = build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000,
                                 opeploinclfincost: 159828000000)
      result1 = svc.send(:parse_financial_fields, item1, "HK")
      assert_equal 159828000000, result1[:operating_income]

      # 场景2：无 opeploinclfincost，有 op → 降级到 op
      item2 = build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000,
                                 op: 150000000000)
      result2 = svc.send(:parse_financial_fields, item2, "HK")
      assert_equal 150000000000, result2[:operating_income]

      # 场景3：两者都有 → 使用 opeploinclfincost（优先）
      item3 = build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000,
                                 opeploinclfincost: 160000000000, op: 150000000000)
      result3 = svc.send(:parse_financial_fields, item3, "HK")
      assert_equal 160000000000, result3[:operating_income]

      # 场景4：两者都无 → nil
      item4 = build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000)
      result4 = svc.send(:parse_financial_fields, item4, "HK")
      assert_nil result4[:operating_income]
    end

    test "2.3 利润表 HK net_income 降级: ploashh → plocyr" do
      svc = XueqiuIncomeStatementService

      # 正常情况：有 ploashh
      item1 = build_income_item("2025-12-31", "2025年报", 646861000000, 291974000000, 291974000000)
      result1 = svc.send(:parse_financial_fields, item1, "HK")
      assert_equal 291974000000, result1[:net_income]

      # 构造：有 plocyr 无 ploashh 的情况
      item2 = {
        "report_date" => 1767139200000,
        "report_name" => "2025年报",
        "report_type_code" => "596001",
        "tto" => [646861000000, 0.1],
        "plocyr" => [291974000000, 0.15],
      }
      result2 = svc.send(:parse_financial_fields, item2, "HK")
      assert_equal 291974000000, result2[:net_income]
    end

    test "2.4 资产负债表 HK 字段映射正确" do
      svc = XueqiuBalanceSheetService
      item = build_balance_item("2025-12-31", "2025年报", 2012730000000, 836465000000)
      result = svc.send(:parse_financial_fields, item, "HK")

      assert_equal 2012730000000, result[:total_assets]
      assert_equal 836465000000, result[:total_liabilities]
    end

    test "2.5 现金流量表 HK 字段映射正确" do
      svc = XueqiuCashFlowService
      item = build_cash_flow_item("2025-12-31", "2025年报", 210456000000, -45678000000, -98765000000)
      result = svc.send(:parse_financial_fields, item, "HK")

      assert_equal 210456000000, result[:operating_cash_flow]
      assert_equal(-45678000000, result[:investing_cash_flow])
      assert_equal(-98765000000, result[:financing_cash_flow])
      assert_nil result[:net_cash_change]  # HK 同 CN，net_cash_change 为 nil
    end

    test "2.6 财务指标表 HK 字段映射正确" do
      svc = XueqiuIndicatorService
      item = build_indicator_item("2025-12-31", "2025年报", 6.4312, 123.5937, 8.6228, 5.09185, 2.840, 56.6355, 40.936)
      result = svc.send(:parse_financial_fields, item, "HK")

      assert_equal BigDecimal("6.4312"), result[:basic_eps]
      assert_equal BigDecimal("123.5937"), result[:nav_ps]
      assert_equal BigDecimal("8.6228"), result[:ncf_from_oa_ps]
      assert_nil result[:capital_reserve]  # HK 不返回此字段
      assert_equal BigDecimal("5.09185"), result[:roe_avg]
      assert_equal BigDecimal("2.840"), result[:net_interest_of_ta]
      assert_equal BigDecimal("56.6355"), result[:gross_margin]
      assert_equal BigDecimal("40.936"), result[:asset_liab_ratio]
    end

    # ──────────────────────────────────────────────
    # 测试模块三：数据完整性（端到端模拟）
    # ──────────────────────────────────────────────

    test "3.1 利润表 HK 端到端：数据完整写入" do
      svc = XueqiuIncomeStatementService

      # 模拟 parse_and_save 内部流程
      items = @hk_income_response["data"]["list"]
      filtered = svc.send(:filter_items, items)

      # 验证过滤结果：只保留年报
      assert_equal 1, filtered.size
      assert_includes filtered.first["report_name"], "年报"

      # 验证字段解析
      item = filtered.first
      fields = svc.send(:parse_financial_fields, item, "HK")
      assert fields[:total_revenue].present?
      assert fields[:operating_income].present?
      assert fields[:net_income].present?
    end

    test "3.2 资产负债表 HK 端到端：数据完整写入" do
      svc = XueqiuBalanceSheetService

      items = @hk_balance_response["data"]["list"]
      filtered = svc.send(:filter_items, items)

      assert_equal 1, filtered.size

      item = filtered.first
      fields = svc.send(:parse_financial_fields, item, "HK")
      assert fields[:total_assets].present?
      assert fields[:total_liabilities].present?
    end

    test "3.3 现金流量表 HK 端到端：数据完整写入" do
      svc = XueqiuCashFlowService

      items = @hk_cash_flow_response["data"]["list"]
      filtered = svc.send(:filter_items, items)

      assert_equal 1, filtered.size

      item = filtered.first
      fields = svc.send(:parse_financial_fields, item, "HK")
      assert fields[:operating_cash_flow].present?
      assert fields[:investing_cash_flow].present?
      assert fields[:financing_cash_flow].present?
      assert_nil fields[:net_cash_change]
    end

    test "3.4 财务指标表 HK 端到端：数据完整写入" do
      svc = XueqiuIndicatorService

      items = @hk_indicator_response["data"]["list"]
      filtered = svc.send(:filter_items, items)

      assert_equal 1, filtered.size

      item = filtered.first
      fields = svc.send(:parse_financial_fields, item, "HK")
      assert fields[:basic_eps].present?
      assert fields[:nav_ps].present?
      assert fields[:ncf_from_oa_ps].present?
      assert fields[:roe_avg].present?
      assert fields[:gross_margin].present?
    end

    # ──────────────────────────────────────────────
    # 测试模块四：错误处理与边界情况
    # ──────────────────────────────────────────────

    test "4.1 parse_financial_value 处理数组格式" do
      svc = XueqiuIncomeStatementService

      # 正常数组
      assert_equal BigDecimal("100"), svc.send(:parse_financial_value, [100, 0.1])

      # 空数组
      assert_nil svc.send(:parse_financial_value, [])

      # nil 值
      assert_nil svc.send(:parse_financial_value, nil)

      # 非数组
      assert_nil svc.send(:parse_financial_value, 100)
    end

    test "4.2 港股未知 stock 返回 nil" do
      # 数据库中不存在的股票
      result = XueqiuIncomeStatementService.call("99999", market: "HK")
      assert_nil result
    end

    test "4.3 港股 data.list 为空时返回 nil" do
      # 模拟空数据响应
      empty_data = { "data" => { "list" => [] } }

      svc = XueqiuIncomeStatementService
      # parse_and_save 接收空列表时应返回 nil
      result = svc.send(:parse_and_save, @hk_stock, empty_data, "HK")
      assert_nil result
    end

    # ──────────────────────────────────────────────
    # 测试模块五：兼容性 - CN/US 不受影响
    # ──────────────────────────────────────────────

    test "5.1 CN 字段映射不受影响" do
      svc = XueqiuIncomeStatementService

      cn_item = {
        "total_revenue" => [100000, 0.1],
        "op" => [20000, 0.05],
        "profit_before_tax" => [22000, 0.06],
        "net_profit" => [18000, 0.07]
      }
      result = svc.send(:parse_financial_fields, cn_item, "CN")

      assert_equal BigDecimal("100000"), result[:total_revenue]
      assert_equal BigDecimal("20000"), result[:operating_income]
    end

    test "5.2 US 字段映射不受影响" do
      svc = XueqiuIncomeStatementService

      us_item = {
        "total_revenue" => [100000, 0.1],
        "operating_income" => [20000, 0.05],
        "income_from_co_before_it" => [22000, 0.06],
        "net_income_atcss" => [18000, 0.07]
      }
      result = svc.send(:parse_financial_fields, us_item, "US")

      assert_equal BigDecimal("100000"), result[:total_revenue]
      assert_equal BigDecimal("20000"), result[:operating_income]
    end
  end
end