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
end