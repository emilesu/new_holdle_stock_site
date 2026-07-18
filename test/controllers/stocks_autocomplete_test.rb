require "test_helper"

class StocksAutocompleteTest < ActionDispatch::IntegrationTest
  test "autocomplete returns results for partial symbol match" do
    get autocomplete_stocks_path(q: "AA"), as: :json
    assert_response :success

    data = response.parsed_body
    assert_kind_of Array, data
    assert data.any? { |s| s["symbol"] == "AAPL" }
  end

  test "autocomplete returns results for partial name match" do
    get autocomplete_stocks_path(q: "App"), as: :json
    assert_response :success

    data = response.parsed_body
    assert_kind_of Array, data
    assert data.any? { |s| s["name"] == "Apple" }
  end

  test "autocomplete returns results for Chinese stock code" do
    get autocomplete_stocks_path(q: "0001"), as: :json
    assert_response :success

    data = response.parsed_body
    assert_kind_of Array, data
    assert data.any? { |s| s["symbol"] == "000001" }
  end

  test "autocomplete includes market labels" do
    get autocomplete_stocks_path(q: "AAPL"), as: :json
    assert_response :success

    data = response.parsed_body
    apple = data.find { |s| s["symbol"] == "AAPL" }
    assert apple
    assert_equal "美股", apple["market_label"]
  end

  test "autocomplete limits results" do
    15.times { |i| Stock.create!(symbol: "TEST#{i}", name: "Test #{i}", market: "US") }

    get autocomplete_stocks_path(q: "TEST"), as: :json
    assert_response :success

    data = response.parsed_body
    assert data.length <= 10
  end

  test "autocomplete rejects empty query" do
    get autocomplete_stocks_path(q: ""), as: :json
    assert_response :success
    assert_equal [], response.parsed_body
  end

  test "autocomplete case insensitive" do
    get autocomplete_stocks_path(q: "aapl"), as: :json
    assert_response :success

    data = response.parsed_body
    assert data.any? { |s| s["symbol"] == "AAPL" }
  end

  test "autocomplete results include url for navigation" do
    get autocomplete_stocks_path(q: "AAPL"), as: :json
    assert_response :success

    data = response.parsed_body
    apple = data.find { |s| s["symbol"] == "AAPL" }
    assert apple
    assert apple["url"].present?
    assert_match /\/stocks\//, apple["url"]
  end

  test "autocomplete matches pinyin initials for CN stocks" do
    get autocomplete_stocks_path(q: "pa"), as: :json
    assert_response :success

    data = response.parsed_body
    pingan = data.find { |s| s["symbol"] == "000001" }
    assert pingan, "搜索 'pa' 应匹配 pinyin_initials 以 'PA' 开头的股票（平安银行 PAYH）"
    assert_equal "平安银行", pingan["name"]
  end

  test "autocomplete matches pinyin initials for HK stocks" do
    get autocomplete_stocks_path(q: "tx"), as: :json
    assert_response :success

    data = response.parsed_body
    tencent = data.find { |s| s["symbol"] == "0700" }
    assert tencent, "搜索 'tx' 应匹配港股（腾讯控股 TXKG）"
    assert_equal "腾讯控股", tencent["name"]
  end

  test "autocomplete does not match pinyin for US stocks" do
    # US 股票的 pinyin_initials 为 nil，不应通过拼音匹配
    # 搜索 'pa' 能匹配 PAYH（平安银行），但不应该通过拼音匹配到 AAPL
    get autocomplete_stocks_path(q: "pa"), as: :json
    assert_response :success

    data = response.parsed_body
    no_apple = data.find { |s| s["symbol"] == "AAPL" }
    assert_nil no_apple, "US 股票（Apple）的 pinyin_initials 为 nil，不应通过拼音匹配 'pa'"
  end

  test "autocomplete pinyin search is case insensitive" do
    get autocomplete_stocks_path(q: "PA"), as: :json
    assert_response :success

    data = response.parsed_body
    pingan = data.find { |s| s["symbol"] == "000001" }
    assert pingan, "大写搜索 'PA' 也应匹配平安银行"
    assert_equal "平安银行", pingan["name"]
  end

  test "autocomplete pinyin prefix only, not arbitrary substring" do
    # pinyin_initials 使用前缀匹配，搜索 'a' 不应匹配所有含 'A' 的拼音
    get autocomplete_stocks_path(q: "a"), as: :json
    assert_response :success

    data = response.parsed_body
    matched_stocks = data.select { |s| %w[000001 600036 0700].include?(s["symbol"]) }
    # 'a' 不会匹配 PAYH、ZSYH、TXKG 中的任一个前缀
    assert matched_stocks.empty?, "拼音搜索使用前缀匹配，'a' 不应匹配任何中文股票"
  end
end