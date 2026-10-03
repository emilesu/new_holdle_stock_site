# 一次性数据回填：把旧 message_boards 每行拆成 1~2 条会话消息。
# - content → user 消息（继承原 created_at / is_read / deleted_at）
# - reply_content 存在 → admin 消息（created_at = replied_at || updated_at；is_read 置 true，
#   避免历史回复在上线瞬间给所有用户点亮红点）
# 纯 SQL 执行，不依赖模型（旧模型类将在本次改造中删除）。
# 旧表 message_boards 物理保留一个版本作回滚保险，线上验证无误后下一版再 drop。
class BackfillMessagesFromMessageBoards < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:message_boards)

    execute <<~SQL
      INSERT INTO messages (user_id, sender, content, is_read, deleted_at, created_at, updated_at)
      SELECT user_id, 'user', content, COALESCE(is_read, FALSE), deleted_at, created_at, updated_at
      FROM message_boards
    SQL

    execute <<~SQL
      INSERT INTO messages (user_id, sender, content, is_read, deleted_at, created_at, updated_at)
      SELECT user_id, 'admin', reply_content, TRUE, deleted_at,
             COALESCE(replied_at, updated_at), COALESCE(replied_at, updated_at)
      FROM message_boards
      WHERE reply_content IS NOT NULL AND reply_content <> ''
    SQL
  end

  def down
    # 数据迁移为单向：回填后无法区分「迁移来的消息」与「新会话消息」，
    # 回滚代码版本即可（旧表数据未动），此处不做删除。
  end
end
