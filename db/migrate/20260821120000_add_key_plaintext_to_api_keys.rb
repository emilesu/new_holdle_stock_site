class AddKeyPlaintextToApiKeys < ActiveRecord::Migration[7.1]
  def change
    add_column :api_keys, :key_plaintext, :text, comment: "Key 明文（Rails 加密存储，供 profile 页展示与复制）"
  end
end
