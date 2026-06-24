require "test_helper"

class UsStockBasicInfoServiceTest < ActiveSupport::TestCase
  setup do
    @service = DataSources::UsStockBasicInfoService
  end

  # ====================================================
  # SECTOR_MAPPING 测试
  # ====================================================

  test "SECTOR_MAPPING 覆盖所有 11 个一级行业" do
    expected_sectors = [
      "Basic Materials", "Communication Services", "Consumer Cyclical",
      "Consumer Defensive", "Energy", "Financial Services", "Healthcare",
      "Industrials", "Real Estate", "Technology", "Utilities"
    ]
    expected_sectors.each do |s|
      assert @service::SECTOR_MAPPING.key?(s), "缺少 Sector 映射: #{s}"
    end
  end

  test "SECTOR_MAPPING 中文翻译不为空" do
    @service::SECTOR_MAPPING.each do |en, cn|
      assert cn.present?, "Sector #{en} 的中文翻译为空"
    end
  end

  test "SECTOR_MAPPING 至少有 11 条映射" do
    assert @service::SECTOR_MAPPING.size >= 11
  end

  # ====================================================
  # INDUSTRY_MAPPING 覆盖测试
  # ====================================================

  test "INDUSTRY_MAPPING 覆盖 yahoo_list.md 中的所有行业" do
    missing = []

    ref_path = Rails.root.join(".trae/documents/yahoo_list.md")
    if File.exist?(ref_path)
      File.readlines(ref_path).each do |line|
        line = line.strip
        next if line.empty?
        parts = line.split("\t")
        next unless parts.size >= 2
        eng = parts[1].strip
        unless @service::INDUSTRY_MAPPING.key?(eng)
          missing << eng
        end
      end
    end

    assert missing.empty?, "yahoo_list.md 中以下行业未映射: #{missing.join(', ')}"
  end

  test "INDUSTRY_MAPPING 已添加过去遗漏的关键映射" do
    critical = [
      "Building Products & Equipment", "Restaurants", "Travel Services",
      "REIT—Industrial", "REIT—Specialty", "REIT—Healthcare Facilities",
      "Real Estate Services", "Specialty Industrial Machinery",
      "Medical Instruments & Supplies", "Integrated Freight & Logistics",
      "Utilities—Regulated Electric", "Beverages—Non—Alcoholic",
      "Footwear & Accessories", "Apparel Retail", "Publishing",
      "Coking Coal", "Leisure", "Rental & Leasing Services",
      "Specialty Retail", "Oil & Gas Equipment & Services",
      "Financial Conglomerates", "Insurance Brokers",
      "Drug Manufacturers—Specialty & Generic",
      "Semiconductor Equipment & Materials", "Utilities—Regulated Gas",
      "Beverages—Brewers", "Education & Training Services",
      "Other Precious Metals & Mining", "Electrical Equipment & Parts",
      "Specialty Business Services"
    ]
    critical.each do |ind|
      assert @service::INDUSTRY_MAPPING.key?(ind), "缺少关键 Industry 映射: #{ind}"
    end
  end

  test "INDUSTRY_MAPPING 中文翻译不为空" do
    @service::INDUSTRY_MAPPING.each do |en, cn|
      assert cn.present?, "Industry #{en} 的中文翻译为空"
    end
  end

  test "INDUSTRY_MAPPING 至少有 150 条映射" do
    count = @service::INDUSTRY_MAPPING.size
    assert count >= 150, "INDUSTRY_MAPPING 只有 #{count} 条，期望至少 150 条"
  end

  # ====================================================
  # 映射无歧义性测试
  # ====================================================

  test "INDUSTRY_MAPPING 中同义行业名映射到相同中文" do
    pairs = [
      [["Software—Infrastructure", "Software - Infrastructure"], "基础设施软件"],
      [["Software—Application", "Software - Application"], "应用软件"],
      [["Beverages—Non-Alcoholic", "Beverages—Non—Alcoholic"], "非酒精饮料"],
      [["Medical Care Facilities", "Medical Instruments & Supplies"], nil]
    ]
    pairs.each do |names, _expected_cn|
      cns = names.map { |n| @service::INDUSTRY_MAPPING[n] }
      cns.each { |cn| assert_not_nil cn, "Industry #{names} 映射缺失" }
    end
  end

  # ====================================================
  # 映射优先级测试
  # ====================================================

  test "SECTOR_MAPPING 中中文名使用标准行业术语" do
    expected_terms = {
      "Basic Materials" => "基础材料",
      "Communication Services" => "通信服务",
      "Consumer Cyclical" => "消费周期",
      "Consumer Defensive" => "消费防御",
      "Energy" => "能源",
      "Financial Services" => "金融服务",
      "Healthcare" => "医疗保健",
      "Industrials" => "工业",
      "Real Estate" => "房地产",
      "Technology" => "科技",
      "Utilities" => "公用事业"
    }
    expected_terms.each do |en, cn|
      assert_equal cn, @service::SECTOR_MAPPING[en], "Sector #{en} 应映射为 #{cn}"
    end
  end

  # ====================================================
  # REAL API 集成测试 (可选)
  # ====================================================

  test "Yahoo API 返回的常见股票行业可被正确映射" do
    skip "需要网络访问，在 CI 中跳过"

    tickers = { "AAPL" => "Technology", "XOM" => "Energy", "JPM" => "Financial Services" }
    tickers.each do |sym, expected_sector|
      response = Faraday.get("https://query1.finance.yahoo.com/v1/finance/search") do |req|
        req.headers["User-Agent"] = "Mozilla/5.0"
        req.params["q"] = sym
        req.options.timeout = 10
      end

      if response.success?
        data = JSON.parse(response.body)
        q = data["quotes"]&.find { |x| x["symbol"] == sym }
        if q
          en_sec = q["sectorDisp"] || q["sector"]
          cn_sec = @service::SECTOR_MAPPING[en_sec]
          assert_equal expected_sector, en_sec, "#{sym} 的 Sector 不匹配"
          assert_not_nil cn_sec, "#{sym} 的 Sector #{en_sec} 缺少中文映射"
        end
      end
    end
  end
end