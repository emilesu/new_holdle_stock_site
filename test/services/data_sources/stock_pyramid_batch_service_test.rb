require "test_helper"

module DataSources
  # 金字塔批量计算：重点覆盖「指定股票子集」按需重算（溢出置空字段回填后的补算入口）
  class StockPyramidBatchServiceTest < ActiveSupport::TestCase
    test "指定 stock_ids 只重算这批股票，其余不受影响" do
      s1 = stocks(:one)
      s2 = stocks(:two)
      s3 = stocks(:three)

      result = DataSources::StockPyramidBatchService.call(stock_ids: [ s1.id, s2.id ])

      assert_equal 2, result[:total]
      assert_not_nil s1.reload.last_pyramid_calc_at, "子集内股票应被重算"
      assert_not_nil s2.reload.last_pyramid_calc_at, "子集内股票应被重算"
      assert_nil s3.reload.last_pyramid_calc_at, "子集外股票不应被触碰"
    end

    test "limit 限制处理数量（后台测试入口）" do
      result = DataSources::StockPyramidBatchService.call(full_recalc: true, limit: 1)

      assert_equal 1, result[:total]
      assert_equal 1, result[:updated] + result[:skipped] + result[:failed]
    end

    test "after_stock_id 断点只处理更大 id 的股票" do
      first = Stock.order(:id).first
      expected = Stock.where("id > ?", first.id).count

      result = DataSources::StockPyramidBatchService.call(full_recalc: true, after_stock_id: first.id)

      assert_equal expected, result[:total]
    end

    test "增量模式只算 30 天未计算的股票" do
      s1 = stocks(:one)
      s2 = stocks(:two)
      s1.update_columns(last_pyramid_calc_at: 60.days.ago)
      s2.update_columns(last_pyramid_calc_at: 1.day.ago)

      result = DataSources::StockPyramidBatchService.call(full_recalc: false)

      assert_operator result[:total], :>=, 1
      assert_not_nil s1.reload.last_pyramid_calc_at
      assert_equal 1.day.ago.to_date, s2.reload.last_pyramid_calc_at.to_date, "近期已算过的股票应被跳过"
    end
  end
end
