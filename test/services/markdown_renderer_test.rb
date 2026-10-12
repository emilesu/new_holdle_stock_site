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

  # ---- render_safe：AI 生成内容安全渲染白名单（对齐确认稿 §三） ----

  test "render_safe 剥离 script 标签与 on* 事件属性" do
    html = MarkdownRenderer.render_safe(<<~MD)
      <script>alert(1)</script>

      <img src="x" onerror="alert(2)">

      [点我](javascript:alert(3))
    MD
    refute_includes html, "<script"
    refute_includes html, "onerror"
    refute_match %r{href="javascript:}i, html
  end

  test "render_safe 放行 details/summary 折叠块" do
    html = MarkdownRenderer.render_safe("<details open><summary>展开推导</summary>\n\n计算过程\n\n</details>")
    assert_includes html, "<details"
    assert_includes html, "<summary>展开推导</summary>"
    assert_includes html, "计算过程"
  end

  test "render_safe 保留表格包裹与常规排版标签" do
    html = MarkdownRenderer.render_safe("|a|\n|---|\n|1|\n\n**加粗** 与 [链接](https://holdle.com)")
    assert_includes html, '<div class="md-table-wrap">'
    assert_includes html, "<strong>加粗</strong>"
    assert_includes html, 'href="https://holdle.com"'
  end
end
