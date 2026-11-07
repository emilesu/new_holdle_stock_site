# 账号归并（PR-5）：把源账号的全部业务数据与登录凭据迁移进目标账号，源账号归档。
# 替代旧启发式合并的 destroy! 级联删除——数据永不物理删除，全程留 MergeLog 审计。
class UserMergeService
  class Error < StandardError; end

  WECHAT_FIELDS = %i[weixin_unionid weixin_web_openid weixin_app_openid].freeze

  attr_reader :source, :target, :admin, :note, :channel

  def initialize(source:, target:, admin: nil, note: nil, channel: "admin")
    @source = source
    @target = target
    @admin = admin
    @note = note
    @channel = channel
  end

  def call
    validate!
    snapshot = source_snapshot

    stats = ActiveRecord::Base.transaction do
      s = { source_id: source.id }
      s[:favorites_dropped] = drop_duplicate_favorites
      s[:favorites_moved] = UserFavorite.where(user_id: source.id).update_all(user_id: target.id)
      s[:messages] = source.messages.update_all(user_id: target.id)
      s[:orders] = source.orders.update_all(user_id: target.id)
      s[:usage_logs] = source.usage_logs.update_all(user_id: target.id)
      s[:api_key_adjustments] = source.api_key_adjustments.update_all(user_id: target.id)
      s.merge!(move_api_keys)
      s.merge!(move_wechat_credentials)
      s.merge!(move_identities)
      archive_source!
      s
    end

    MergeLog.create!(
      source_user_id: source.id,
      target_user_id: target.id,
      admin_user_id: admin&.id,
      channel: channel,
      payload: { snapshot: snapshot, stats: stats }.to_json,
      note: note
    )
    stats
  end

  private

  def validate!
    raise Error, "源账号与目标账号不能相同" if source.id == target.id
    raise Error, "源账号已归档" if source.archived_at.present?
    raise Error, "目标账号已归档，不能作为归并目标" if target.archived_at.present?
  end

  # 目标账号已收藏同股票的记录保留目标的星级，源重复项删除（无业务价值，非用户数据损失）
  def drop_duplicate_favorites
    dup_ids = UserFavorite.where(user_id: source.id)
                          .where(stock_id: UserFavorite.where(user_id: target.id).select(:stock_id))
                          .pluck(:id)
    UserFavorite.where(id: dup_ids).delete_all
  end

  # 目标已有 active key 时，源的 active key 先降级为 disabled，避免目标出现双活 key
  def move_api_keys
    disabled = target.api_keys.active.exists? ? source.api_keys.active.update_all(status: "disabled", disabled_reason: "账号归并自动停用") : 0
    moved = source.api_keys.update_all(user_id: target.id)
    { api_keys_moved: moved, api_keys_disabled: disabled }
  end

  # 目标缺哪个微信字段就从源补哪个；目标已有的保持不动（源的旧值随归档清除并留在快照里）。
  # 必须先清源再写目标：两行同表同唯一索引，反方向写会瞬间撞键
  def move_wechat_credentials
    moved = {}
    WECHAT_FIELDS.each do |field|
      value = source.public_send(field)
      next if value.blank?
      if target.public_send(field).blank?
        source.update_column(field, nil)
        target.update_column(field, value)
        moved[field] = value
      end
    end
    { wechat_moved: moved }
  end

  # 用独立查询而非缓存关联迭代：update_column 改 user_id 后记录已不属于源，
  # 若用 source.identities 的加载缓存，归档 destroy_all 会误删刚迁走的凭据
  def move_identities
    moved = 0
    dropped = 0
    Identity.where(user_id: source.id).find_each do |identity|
      if Identity.where(user_id: target.id, provider: identity.provider).exists?
        dropped += 1
      else
        identity.update_column(:user_id, target.id)
        moved += 1
      end
    end
    { identities_moved: moved, identities_dropped: dropped }
  end

  def archive_source!
    source.update_columns(
      archived_at: Time.current,
      email: "archived-#{source.id}@invalid.local",
      weixin_unionid: nil,
      weixin_web_openid: nil,
      weixin_app_openid: nil,
      reset_password_token: nil,
      reset_password_sent_at: nil
    )
    # 未迁移走的残留凭据随归档销毁（快照里留有记录）；独立查询避免关联缓存误删已迁走记录
    Identity.where(user_id: source.id).destroy_all
  end

  def source_snapshot
    {
      id: source.id,
      email: source.email,
      nickname: source.nickname,
      role: source.role,
      member_expire_at: source.member_expire_at&.iso8601,
      created_at: source.created_at.iso8601,
      weixin_unionid: source.weixin_unionid,
      weixin_web_openid: source.weixin_web_openid,
      weixin_app_openid: source.weixin_app_openid,
      identities: source.identities.map { |i| { provider: i.provider, uid: i.uid, email: i.email } },
      counts: {
        favorites: source.user_favorites.count,
        messages: source.messages.count,
        orders: source.orders.count,
        api_keys: source.api_keys.count
      }
    }
  end
end
