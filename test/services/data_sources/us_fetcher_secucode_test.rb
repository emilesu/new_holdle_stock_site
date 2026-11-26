require "test_helper"

# UsFetcher#resolve_secucode：特殊字符 symbol 的归一化查询与重试条件
# 背景：库内 BRK/B 等斜杠格式曾原样查东财导致 SECUCODE 解析失败、财务数据全缺
class UsFetcherSecucodeTest < ActiveSupport::TestCase
  Fetcher = DataSources::Fetchers::UsFetcher

  setup do
    @fetcher = Fetcher.new
    @requests = []
  end

  # stub http_get：记录每次请求 filter 中的 SECURITY_CODE，命中判定由 hit 决定
  def stub_api(&hit)
    requests = @requests
    @fetcher.define_singleton_method(:http_get) do |_url, opts|
      filter = opts[:params][:filter]
      code = filter[/SECURITY_CODE="([^"]*)"/, 1]
      requests << code
      rows = hit.call(code)
      { "result" => { "data" => rows, "pages" => 1 } }
    end
  end

  test "含斜杠代码转下划线查询并命中" do
    stub_api { |code| code == "BRK_B" ? [{ "SECUCODE" => "BRK_B.N" }] : [] }

    assert_equal "BRK_B.N", @fetcher.send(:resolve_secucode, "BRK/B")
    assert_equal ["BRK_B"], @requests
  end

  test "含脱字符代码转下划线查询" do
    stub_api { |code| code == "NLY_F" ? [{ "SECUCODE" => "NLY_F.N" }] : [] }

    assert_equal "NLY_F.N", @fetcher.send(:resolve_secucode, "NLY^F")
    assert_equal ["NLY_F"], @requests
  end

  test "含斜杠代码查不到时不用原始 symbol 重试（原样格式实测必空）" do
    stub_api { |_| [] }

    assert_nil @fetcher.send(:resolve_secucode, "AKO/A")
    assert_equal ["AKO_A"], @requests, "含 / 或 ^ 的代码只查一次，避免注定失败的重试"
  end

  test "含点代码查不到时回退原始点号格式重试一次" do
    stub_api { |code| code == "BF.B" ? [{ "SECUCODE" => "BF.B.N" }] : [] }

    assert_equal "BF.B.N", @fetcher.send(:resolve_secucode, "BF.B")
    assert_equal %w[BF_B BF.B], @requests
  end
end
