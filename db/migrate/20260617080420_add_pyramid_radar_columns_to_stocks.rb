class AddPyramidRadarColumnsToStocks < ActiveRecord::Migration[7.1]
  def change
    # 金字塔总分
    add_column :stocks, :pyramid_total_score, :integer, default: 0, null: false unless column_exists?(:stocks, :pyramid_total_score)
    # 金字塔上次计算时间
    add_column :stocks, :last_pyramid_calc_at, :datetime unless column_exists?(:stocks, :last_pyramid_calc_at)
    # 雷达6维度预计算缓存jsonb
    add_column :stocks, :radar_dim_scores, :jsonb unless column_exists?(:stocks, :radar_dim_scores)

    # 排行榜联合索引：先判断索引不存在再创建
    unless index_exists?(:stocks, [:market, :sector, :pyramid_total_score])
      add_index :stocks, [:market, :sector, :pyramid_total_score], order: { pyramid_total_score: :desc }
    end

    # 雷达维度GIN索引
    unless index_exists?(:stocks, :radar_dim_scores)
      add_index :stocks, :radar_dim_scores, using: :gin
    end
  end
end