class AddWechatOauthFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    # UnionID：跨端唯一主键（最高优先级）
    add_column :users, :weixin_unionid, :string unless column_exists?(:users, :weixin_unionid)
    # 旧系统网页Openid，兼容历史用户
    add_column :users, :weixin_web_openid, :string unless column_exists?(:users, :weixin_web_openid)
    # 预留未来APP微信Openid
    add_column :users, :weixin_app_openid, :string unless column_exists?(:users, :weixin_app_openid)

    # 唯一索引，登录快速匹配
    unless index_exists?(:users, :weixin_unionid)
      add_index :users, :weixin_unionid, unique: true
    end
    unless index_exists?(:users, :weixin_web_openid)
      add_index :users, :weixin_web_openid, unique: true
    end
    unless index_exists?(:users, :weixin_app_openid)
      add_index :users, :weixin_app_openid, unique: true
    end
  end
end