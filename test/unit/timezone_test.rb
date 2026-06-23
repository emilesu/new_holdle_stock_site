require "test_helper"

class TimezoneTest < ActiveSupport::TestCase
  test "Rails time_zone is configured as Asia/Shanghai" do
    assert_equal "Asia/Shanghai", Rails.application.config.time_zone
  end

  test "Time.current returns time in configured timezone" do
    Time.use_zone("Asia/Shanghai") do
      now = Time.current
      assert_equal "Asia/Shanghai", now.time_zone.name
    end
  end

  test "Date.current returns date in configured timezone" do
    Time.use_zone("Asia/Shanghai") do
      today = Date.current
      now_local = Time.current.in_time_zone("Asia/Shanghai")
      assert_equal now_local.to_date, today
    end
  end

  test "Time.zone.at correctly converts timestamps to Beijing time" do
    beijing_midnight = Time.use_zone("Asia/Shanghai") { Time.zone.parse("2026-06-23 00:00:00") }
    unix_timestamp = beijing_midnight.to_i

    converted = Time.zone.at(unix_timestamp)
    assert_equal beijing_midnight, converted
    assert_equal "Asia/Shanghai", converted.time_zone.name
  end

  test "Database stores UTC and reads back as configured timezone" do
    user = users(:one)
    now_beijing = Time.use_zone("Asia/Shanghai") { Time.zone.now }

    user.update!(last_login_at: now_beijing)

    user.reload
    read_back = user.last_login_at.in_time_zone("Asia/Shanghai")
    assert_equal now_beijing.strftime("%Y-%m-%d %H:%M"), read_back.strftime("%Y-%m-%d %H:%M")
  end

  test "cache keys use Date.current for consistent Beijing date" do
    Time.use_zone("Asia/Shanghai") do
      today = Date.current
      expected_key = "test_cache_key_#{today}"
      actual_key = "test_cache_key_#{Date.current}"
      assert_equal expected_key, actual_key
    end
  end

  test "all Date.today have been replaced with Date.current" do
    Dir.glob(Rails.root.join("app", "**", "*.{rb,erb}")).each do |file|
      content = File.read(file)
      refute_match(/Date\.today\b/, content,
        "Found Date.today in #{file} \u2014 should use Date.current")
    end
  end
end