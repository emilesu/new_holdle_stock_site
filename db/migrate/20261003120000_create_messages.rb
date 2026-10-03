# 微信式会话消息表：每行 = 一条消息，会话按 user_id 隐式聚合（1 用户 ↔ 站长一条连续会话）。
# 取代旧 message_boards 表的「一行 = 一条留言 + 单个回复字段」形态——旧形态管理员只能回复一次且会覆盖，
# 无法支持多轮问答。is_read 语义为「接收方已读」：user 消息看站长是否读过（后台未读数），
# admin 消息看用户是否读过（前台悬浮按钮红点）。
class CreateMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :messages, comment: "会话消息（用户↔站长多轮问答，按user_id聚合为一条会话）" do |t|
      t.bigint :user_id, null: false, comment: "会话归属用户ID，关联users表"
      t.string :sender, null: false, comment: "发送方（user=用户 / admin=站长大苏）"
      t.text :content, null: false, comment: "消息内容"
      t.boolean :is_read, default: false, null: false, comment: "接收方是否已读（user消息=站长已读；admin消息=用户已读）"
      t.datetime :deleted_at, comment: "软删除时间，非空代表已隐藏"

      t.timestamps
    end

    # 会话流查询（user_id 过滤 + created_at 排序）与后台按用户聚合
    add_index :messages, [ :user_id, :created_at ]
    add_index :messages, :is_read
    add_foreign_key :messages, :users
  end
end
