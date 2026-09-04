require "test_helper"

class AlipayWapResolverTest < ActiveSupport::TestCase
  test "跟随 302 重定向返回 mclient 收银台地址" do
    resp = Struct.new(:status, :headers).new
    resp.status = 302
    resp.headers = { "location" => "https://mclient.alipay.com/h5pay/h5RouteAppSenior/index.html?cookieToken=xx" }

    Faraday.stub(:get, ->(_url, &_blk) { resp }) do
      assert_equal "https://mclient.alipay.com/h5pay/h5RouteAppSenior/index.html?cookieToken=xx",
                   AlipayWapResolver.resolve("https://openapi.alipay.com/gateway.do?app_id=1")
    end
  end

  test "请求异常时回退原网关 URL" do
    Faraday.stub(:get, ->(_url, &_blk) { raise Faraday::ConnectionFailed, "boom" }) do
      assert_equal "https://openapi.alipay.com/gateway.do?app_id=1",
                   AlipayWapResolver.resolve("https://openapi.alipay.com/gateway.do?app_id=1")
    end
  end
end