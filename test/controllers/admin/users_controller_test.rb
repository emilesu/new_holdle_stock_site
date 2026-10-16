require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:two) # role: admin
    sign_in @admin
    @user = users(:one)

    Plan.create!(plan_code: "starter", name: "尝鲜包", price_cents: 500, quota: 20)
    Plan.create!(plan_code: "member_permanent", name: "永久会员", price_cents: 46_800, quota: nil, is_member_upgrade: true)
  end

  def build_key(user, plan_code: "starter", quota: 20, status: "active")
    plain = "hl_" + SecureRandom.hex(8)
    ApiKey.create!(
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      user: user,
      plan_code: plan_code,
      status: status,
      quota_remaining: quota,
      quota_total: quota
    )
  end

  test "调整次数：加次数并写入调整记录" do
    key = build_key(@user, quota: 20)

    post adjust_api_key_quota_admin_user_path(@user), params: { delta: 5, reason: "测试补偿" }

    assert_redirected_to edit_admin_user_path(@user)
    assert_equal 25, key.reload.quota_remaining
    adjustment = key.api_key_adjustments.last
    assert_equal 5, adjustment.delta
    assert_equal "测试补偿", adjustment.reason
    assert_equal @admin.id, adjustment.admin_id
  end

  test "调整次数：减次数不低到负数，审计记录按实际生效值" do
    key = build_key(@user, quota: 3)

    post adjust_api_key_quota_admin_user_path(@user), params: { delta: -10, reason: "测试扣减" }

    assert_equal 0, key.reload.quota_remaining
    assert_equal(-3, key.api_key_adjustments.last.delta, "超扣时应按实际生效值记录")
  end

  test "调整次数：无限次会员 key 不允许调整" do
    key = build_key(@user, plan_code: "member_permanent", quota: nil)

    post adjust_api_key_quota_admin_user_path(@user), params: { delta: 5, reason: "测试" }

    assert_redirected_to edit_admin_user_path(@user)
    assert_match "无限次", flash[:alert].to_s
    assert_equal 0, key.api_key_adjustments.count
  end

  test "吊销 key：状态变为 disabled（可恢复）" do
    key = build_key(@user)

    post disable_api_key_admin_user_path(@user)

    assert_equal "disabled", key.reload.status
  end

  test "启用 key：disabled 恢复为 active" do
    key = build_key(@user, status: "disabled")

    post enable_api_key_admin_user_path(@user)

    assert_equal "active", key.reload.status
    assert_nil key.disabled_reason
  end

  test "重新生成 key：旧 key 吊销 + 生成同套餐新 key" do
    old_key = build_key(@user, quota: 20)

    post regenerate_api_key_admin_user_path(@user)

    assert_equal "revoked", old_key.reload.status
    new_key = @user.api_keys.active.first
    assert new_key.present?, "应生成新的 active key"
    assert_not_equal old_key.id, new_key.id
    assert_equal "starter", new_key.plan_code
    assert_equal 20, new_key.quota_remaining
  end

  test "普通用户无 key 时调整次数给出提示" do
    post adjust_api_key_quota_admin_user_path(@user), params: { delta: 5, reason: "测试" }

    assert_redirected_to edit_admin_user_path(@user)
    assert_match "没有 active key", flash[:alert].to_s
  end

  test "非管理员访问被重定向" do
    sign_out @admin
    sign_in users(:one)

    post adjust_api_key_quota_admin_user_path(@user), params: { delta: 5, reason: "x" }

    assert_redirected_to new_user_session_path
  end

  test "后台改 role 为 member 且旧到期已过期时自动顺延生效" do
    @user.update_columns(member_expire_at: 1.year.ago) # role 仍为 user，模拟早年过期会员
    expired_date = @user.member_expire_at.to_date.to_s

    patch admin_user_path(@user), params: {
      user: { email: @user.email, nickname: @user.nickname, role: "member", member_expire_at: expired_date }
    }

    assert @user.reload.is_member?, "改 role 后过期的到期时间应被模型自动顺延"
    assert_match "更新成功", flash[:notice].to_s
  end

  test "后台保存 member 但到期时间仍过期时提示会员功能不可用" do
    @user.update_columns(role: "member", member_expire_at: 1.year.ago)
    expired_date = @user.member_expire_at.to_date.to_s

    patch admin_user_path(@user), params: {
      user: { email: @user.email, nickname: @user.nickname, role: "member", member_expire_at: expired_date }
    }

    assert_redirected_to admin_user_path(@user)
    assert_match "到期", flash[:alert].to_s
    assert_not @user.reload.is_member?, "未改 role 时不应被擅自顺延"
  end
end
