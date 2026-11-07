require "test_helper"

# PR-5 账号归并服务：数据迁移、凭据补位、归档与审计
class UserMergeServiceTest < ActiveSupport::TestCase
  setup do
    @source = users(:one)
    @target = users(:two)
    @stock_a = stocks(:one)
    @stock_b = stocks(:two)
  end

  test "迁移收藏/订单并对同股票收藏去重（保留目标星级）" do
    @source.favorite!(@stock_a, rating: 3)
    @target.favorite!(@stock_a, rating: 5)
    @source.favorite!(@stock_b)
    Order.create!(user: @source, amount_cents: 46_800)

    stats = UserMergeService.new(source: @source, target: @target, note: "test").call

    assert_equal 1, stats[:favorites_moved]
    assert_equal 1, stats[:favorites_dropped]
    assert_equal 5, UserFavorite.find_by(user: @target, stock: @stock_a).rating
    assert_equal 2, @target.user_favorites.count
    assert_equal 1, @target.orders.count
  end

  test "目标已有 active key 时源 active key 停用后一并迁移" do
    plain = "hl_" + SecureRandom.hex(8)
    target_key = ApiKey.create!(key_hash: Digest::SHA256.hexdigest(plain), key_prefix: plain[0, 11],
                                user: @target, plan_code: "starter", status: "active", quota_remaining: 5, quota_total: 5)
    plain2 = "hl_" + SecureRandom.hex(8)
    source_key = ApiKey.create!(key_hash: Digest::SHA256.hexdigest(plain2), key_prefix: plain2[0, 11],
                                user: @source, plan_code: "starter", status: "active", quota_remaining: 9, quota_total: 9)

    stats = UserMergeService.new(source: @source, target: @target).call

    assert_equal 1, stats[:api_keys_moved]
    assert_equal 1, stats[:api_keys_disabled]
    assert target_key.reload.active?
    source_key.reload
    assert_equal @target.id, source_key.user_id
    assert_equal "disabled", source_key.status
  end

  test "微信凭据补入目标空缺字段且源归档清凭据" do
    @source.update!(weixin_unionid: "u_src", weixin_web_openid: "w_src")
    @target.update!(weixin_app_openid: "a_tgt")

    UserMergeService.new(source: @source, target: @target).call

    @target.reload
    assert_equal "u_src", @target.weixin_unionid
    assert_equal "w_src", @target.weixin_web_openid
    assert_equal "a_tgt", @target.weixin_app_openid
    @source.reload
    assert_nil @source.weixin_unionid
    assert_predicate @source, :archived?
    assert_match(/\Aarchived-\d+@invalid\.local\z/, @source.email)
  end

  test "Google 凭据迁移：同 provider 冲突则丢弃源侧（快照留痕）" do
    @target.identities.create!(provider: "google_oauth2", uid: "g_tgt", email: "t@gmail.com")
    @source.identities.create!(provider: "google_oauth2", uid: "g_src", email: "s@gmail.com")
    @source.identities.create!(provider: "github", uid: "gh1", email: nil)

    stats = UserMergeService.new(source: @source, target: @target).call

    assert_equal 1, stats[:identities_moved]
    assert_equal 1, stats[:identities_dropped]
    assert @target.reload.identities.exists?(uid: "gh1")
    assert_not @target.identities.exists?(uid: "g_src")
    assert_equal 0, Identity.where(user_id: @source.id).count
  end

  test "审计日志记录源快照与计数" do
    @source.favorite!(@stock_a)
    UserMergeService.new(source: @source, target: @target, note: "工单#1").call

    log = MergeLog.sole
    assert_equal @source.id, log.source_user_id
    assert_equal @target.id, log.target_user_id
    assert_equal "工单#1", log.note
    assert_equal "user1@test.com", log.payload_json["snapshot"]["email"]
    assert_equal 1, log.payload_json["snapshot"]["counts"]["favorites"]
  end

  test "校验拦截：源同目标 / 任一方已归档" do
    assert_raises(UserMergeService::Error) { UserMergeService.new(source: @source, target: @source).call }

    @target.update!(archived_at: Time.current)
    assert_raises(UserMergeService::Error) { UserMergeService.new(source: @source, target: @target).call }
  end

  test "归档账号禁止登录" do
    UserMergeService.new(source: @source, target: @target).call
    assert_not @source.reload.active_for_authentication?
  end
end
