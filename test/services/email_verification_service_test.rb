require "test_helper"

# PR-6 邮箱验证码服务：发码/限流/尝试上限/过期/一次性
class EmailVerificationServiceTest < ActiveSupport::TestCase
  test "issue 发码入库（邮箱归一化小写）并投递邮件" do
    assert_difference "EmailVerification.count", 1 do
      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        EmailVerificationService.issue(email: "Code@Test.com ", purpose: "bind_email", ip: "1.2.3.4")
      end
    end
    assert_equal "code@test.com", EmailVerification.last.email
  end

  test "60 秒内重复获取被拦截" do
    EmailVerificationService.issue(email: "a@t.com", purpose: "bind_email")
    assert_raises(EmailVerificationService::Error) do
      EmailVerificationService.issue(email: "a@t.com", purpose: "bind_email")
    end
  end

  test "同 IP 每小时限流" do
    10.times do |i|
      EmailVerification.create!(email: "u#{i}@t.com", purpose: "bind_email",
                                code_digest: "x", expires_at: 10.minutes.from_now, ip: "9.9.9.9")
    end
    assert_raises(EmailVerificationService::Error) do
      EmailVerificationService.issue(email: "new@t.com", purpose: "bind_email", ip: "9.9.9.9")
    end
  end

  test "verify 正确码通过且一次性销毁" do
    create_record("123456")
    assert EmailVerificationService.verify!(email: "v@t.com", purpose: "bind_email", code: "123456")
    assert_equal 0, EmailVerification.count
  end

  test "错误码计次，5 次后正确码也作废" do
    create_record("123456")
    5.times do
      assert_raises(EmailVerificationService::Error) do
        EmailVerificationService.verify!(email: "v@t.com", purpose: "bind_email", code: "000000")
      end
    end
    err = assert_raises(EmailVerificationService::Error) do
      EmailVerificationService.verify!(email: "v@t.com", purpose: "bind_email", code: "123456")
    end
    assert_match(/错误次数过多/, err.message)
  end

  test "过期码拒绝" do
    record = create_record("123456")
    record.update_column(:expires_at, 11.minutes.ago)
    assert_raises(EmailVerificationService::Error) do
      EmailVerificationService.verify!(email: "v@t.com", purpose: "bind_email", code: "123456")
    end
  end

  private

  def create_record(code)
    EmailVerification.create!(email: "v@t.com", purpose: "bind_email",
                              code_digest: Devise::Encryptor.digest(User, code),
                              expires_at: 10.minutes.from_now)
  end
end
