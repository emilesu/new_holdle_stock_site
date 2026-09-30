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
  end
end
