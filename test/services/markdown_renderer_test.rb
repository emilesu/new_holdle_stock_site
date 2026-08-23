require "test_helper"

# 统一 Markdown 渲染服务的行为锁定测试，防止重构后行为漂移
class MarkdownRendererTest < ActiveSupport::TestCase
  test "渲染表格并包上 md-table-wrap（移动端横向滚动）" do
    html = MarkdownRenderer.render("|a|b|\n|---|---|\n|1|2|")
    assert_includes html, '<div class="md-table-wrap"><table>'
    assert_includes html, '</table></div>'
    assert_includes html, "<td>1</td>"
  end

  test "剥离高亮生成的内联 style" do
    html = MarkdownRenderer.render('<span style="color:red">hi</span>')
    refute_match /style=/, html
  end

  test "nil 输入渲染为空字符串" do
    assert_equal "", MarkdownRenderer.render(nil)
  end
end
