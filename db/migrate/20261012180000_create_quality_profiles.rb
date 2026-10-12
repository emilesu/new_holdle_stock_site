class CreateQualityProfiles < ActiveRecord::Migration[7.1]
  def change
    # 企业质量档案主表：一行 = 一只股票一个财报期（幂等键 stock_id + period）
    # 主表存「最新稿」（可能是待审内容），对外可见内容取 published_version_no 指向的版本快照
    create_table :quality_profiles do |t|
      t.references :stock, null: false, foreign_key: true, comment: "关联股票"
      t.string :period, null: false, comment: "财报期标签（如 2025年报），与取数接口 period 完全一致"
      t.string :title, null: false, comment: "档案标题"
      t.text :markdown, null: false, comment: "最新稿正文（Markdown，待审内容不直接对外）"
      t.jsonb :meta, null: false, default: "{}", comment: "发布元数据快照（data_cutoff/disclosed_at/pyramid_score/pyramid_calc_at/gate_passed/ai_generated 等）"
      t.string :status, null: false, default: "draft", comment: "状态：draft/pending_review/published/withdrawn/superseded"
      t.integer :current_version_no, null: false, default: 0, comment: "当前版本号（每次覆盖发布 +1）"
      t.integer :published_version_no, comment: "对外可见版本号（闸门放行时写入，指向 versions.version_no）"
      t.datetime :published_at, comment: "最近一次发布时间"
      t.references :published_by, null: true, foreign_key: { to_table: :users }, comment: "发布操作人（人工闸门追责）"
      t.datetime :withdrawn_at, comment: "撤回时间"

      t.timestamps
    end
    add_index :quality_profiles, %i[stock_id period], unique: true, name: "idx_quality_profiles_stock_period"
    add_index :quality_profiles, :status

    # 版本表：每次覆盖发布留一份不可变快照，支撑「旧版继续可见」与「回滚」
    create_table :quality_profile_versions do |t|
      t.references :quality_profile, null: false, foreign_key: true, comment: "所属档案"
      t.integer :version_no, null: false, comment: "版本号（从 1 递增）"
      t.string :title, null: false, comment: "该版本标题快照"
      t.text :markdown, null: false, comment: "该版本正文快照"
      t.jsonb :meta, null: false, default: "{}", comment: "该版本元数据快照"

      t.timestamps
    end
    add_index :quality_profile_versions, %i[quality_profile_id version_no], unique: true, name: "idx_qpv_profile_version"
  end
end
