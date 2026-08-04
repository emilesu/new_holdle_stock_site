require "test_helper"

module DataSources
  class EastmoneyDatacenterTest < ActiveSupport::TestCase
    def fake_response(body, success: true)
      resp = Object.new
      resp.define_singleton_method(:success?) { success }
      resp.define_singleton_method(:status) { success ? 200 : 500 }
      resp.define_singleton_method(:body) { body }
      resp
    end

    def fetch_data(**opts)
      EastmoneyDatacenter.fetch_data(
        report_name: "RPT_F10_ORG_BASICINFO",
        columns: "SECUCODE,LISTING_DATE",
        filter: '(SECUCODE="600519.SH")',
        page_size: 1,
        **opts
      )
    end

    test "成功请求返回result.data数组" do
      Faraday.stub(:get, ->(_url) { fake_response('{"result":{"data":[{"LISTING_DATE":"2001-08-27"}]}}') }) do
        data = fetch_data
        assert_equal [{ "LISTING_DATE" => "2001-08-27" }], data
      end
    end

    test "无数据时返回空数组" do
      Faraday.stub(:get, ->(_url) { fake_response('{"result":{"data":[]}}') }) do
        assert_equal [], fetch_data
      end
    end

    test "非2xx且raise_on_failure=false时返回nil" do
      Faraday.stub(:get, ->(_url) { fake_response("", success: false) }) do
        assert_nil fetch_data
      end
    end

    test "非2xx且raise_on_failure=true时抛异常" do
      Faraday.stub(:get, ->(_url) { fake_response("", success: false) }) do
        assert_raises(Faraday::Error) { fetch_data(raise_on_failure: true) }
      end
    end

    test "网络失败重试耗尽且raise_on_failure=true时抛异常" do
      Faraday.stub(:get, ->(_url) { raise Faraday::ConnectionFailed, "connection refused" }) do
        assert_raises(Faraday::ConnectionFailed) { fetch_data(raise_on_failure: true) }
      end
    end

    test "网络失败重试耗尽且raise_on_failure=false时返回nil" do
      Faraday.stub(:get, ->(_url) { raise Faraday::ConnectionFailed, "connection refused" }) do
        assert_nil fetch_data
      end
    end

    test "JSON解析失败且raise_on_failure=false时返回nil" do
      Faraday.stub(:get, ->(_url) { fake_response("invalid json") }) do
        assert_nil fetch_data
      end
    end
  end
end
