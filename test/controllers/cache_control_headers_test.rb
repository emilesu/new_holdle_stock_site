require "test_helper"

# 缓存安全回归测试：鉴权/个性化页面必须输出 private, no-store 禁止 CDN 公共缓存，
# 防止会员内容或 302 重定向响应被缓存后错误回放（2026-09-05 事故）。
class CacheControlHeadersTest < ActionDispatch::IntegrationTest
  test "会员课程小节输出 private no-store" do
    chapter = Chapter.create!(course: Course.create!(title: "缓存测试课", access_level: 1, is_published: true), title: "缓存测试章", access_level: 1, is_published: true)
    lesson = Lesson.create!(chapter: chapter, title: "缓存测试小节", access_level: 1, is_published: true, sort_num: 1)
    get lesson_path(lesson)
    assert_equal "private, no-store", response.headers["Cache-Control"]
  ensure
    lesson&.destroy!
    chapter&.destroy!
    chapter&.course&.destroy!
  end

  test "金字塔页面输出 private no-store" do
    get pyramid_path(market: "CN")
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "公开页面不输出 private no-store（保持可被 CDN 缓存）" do
    get terms_path
    assert_response :success
    assert_not_equal "private, no-store", response.headers["Cache-Control"]
  end
end
