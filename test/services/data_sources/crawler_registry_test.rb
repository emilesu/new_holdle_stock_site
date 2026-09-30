require "test_helper"

module DataSources
  class CrawlerRegistryTest < ActiveSupport::TestCase
    test "任务 key 唯一" do
      keys = CrawlerRegistry.keys
      assert_equal keys.uniq, keys
    end

    test "每个任务都能解析出服务类与入口方法" do
      CrawlerRegistry.all.each do |task|
        assert task.service_class.respond_to?(task.method_name), "#{task.key} 缺少入口方法 #{task.method_name}"
        assert task.name.present?, "#{task.key} 缺少名称"
        assert task.description.present?, "#{task.key} 缺少说明"
        assert CrawlerRegistry::GROUPS.key?(task.group), "#{task.key} 的分组 #{task.group} 未登记"
      end
    end

    test "by_group 覆盖全部任务" do
      grouped = CrawlerRegistry.by_group.values.flatten.map(&:key).sort
      assert_equal CrawlerRegistry.keys.sort, grouped
    end

    test "for_data_type 只返回支持股票子集的任务" do
      tasks = CrawlerRegistry.for_data_type("financial")
      assert_includes tasks.map(&:key), "a_finance"
      assert tasks.all?(&:accepts_stock_scope?)
      assert tasks.all? { |task| task.sync_data_type == "financial" }
    end

    test "find 接受字符串与符号 key" do
      assert_equal "a_finance", CrawlerRegistry.find("a_finance").key
      assert_equal "a_finance", CrawlerRegistry.find(:a_finance).key
      assert_nil CrawlerRegistry.find("not_exist")
    end

    test "重任务标记仅用于耗时长的任务" do
      assert CrawlerRegistry.find("a_finance").heavy?
      refute CrawlerRegistry.find("a_stock_list").heavy?
    end

    # 后台「测试 5 只」按钮的显示条件是 accepts_stock_scope?，触发时固定传 limit=5。
    # CrawlerJob 只透传服务签名里声明过的关键字参数，若服务没声明 limit:，
    # 参数会被静默丢弃 → 点「测试 5 只」实际跑全量（曾有 listing_date 踩坑）
    test "支持股票子集的任务必须声明 limit 关键字参数" do
      CrawlerRegistry.all.select(&:accepts_stock_scope?).each do |task|
        accepted = task.service_class.method(task.method_name)
          .parameters.select { |type, _name| %i[key keyreq].include?(type) }
          .map(&:last)

        assert_includes accepted, :limit, "#{task.key} 未声明 limit:，后台「测试 5 只」会退化成全量"
      end
    end
  end
end
