class CreateMessageBoards < ActiveRecord::Migration[7.0]
  def change
    create_table "message_boards" do |t|
      t.bigint "user_id", null: false
      t.string "username", null: false
      t.string "email", null: false
      t.text "content", null: false
      t.text "reply_content"
      t.datetime "replied_at"
      t.boolean "is_read", default: false
      t.datetime "deleted_at", comment: "软删除时间，非空代表已隐藏"
      t.timestamps
    end
    # 正确语法：add_foreign_key(当前表, 关联表, 选项)
    add_foreign_key "message_boards", "users", on_delete: :cascade

    add_index "message_boards", "user_id"
    add_index "message_boards", "is_read"
    add_index "message_boards", "deleted_at"
  end
end