require "test_helper"

# 课程学员（268）三级权限阶梯回归：access_level 0=公开 / 1=学员 / 2=会员（迁移 20261104120000）
class StudentTierTest < ActiveSupport::TestCase
  setup do
    @visitor = users(:one) # role: user
    @student = User.create!(email: "tier_student@t.com", password: "test1234", nickname: "档位学员", role: "student")
    @member  = User.create!(email: "tier_member@t.com", password: "test1234", nickname: "档位会员", role: "member")
    @admin   = users(:two) # role: admin

    @public_course  = Course.create!(title: "公开冒烟课", is_published: true, access_level: 0)
    @stu_course     = Course.create!(title: "学员冒烟课", is_published: true, access_level: 1)
    @mem_course     = Course.create!(title: "会员冒烟课", is_published: true, access_level: 2)
    @stu_article    = Article.create!(title: "学员冒烟文", is_published: true, access_level: 1)
    @mem_article    = Article.create!(title: "会员冒烟文", is_published: true, access_level: 2)
  end

  test "content_tier 四身份档位矩阵" do
    assert_equal User::TIER_VISITOR, @visitor.content_tier
    assert_equal User::TIER_STUDENT, @student.content_tier
    assert_equal User::TIER_MEMBER, @member.content_tier
    assert_equal User::TIER_MEMBER, @admin.content_tier
  end

  test "available_to? 按档位放行：学员可见学员档不可见会员档" do
    assert @stu_course.available_to?(@student), "学员应可见学员档课程"
    assert @stu_course.available_to?(@member), "会员向上兼容学员档"
    assert_not @stu_course.available_to?(@visitor), "访客不可见学员档"
    assert_not @stu_course.available_to?(nil), "未登录不可见学员档"
    assert_not @mem_course.available_to?(@student), "学员不可见会员档"
    assert @mem_course.available_to?(@member), "会员可见会员档"
    assert @public_course.available_to?(nil), "公开内容所有人可见"
  end

  test "accessible_by 列表过滤：三级各见其档" do
    assert_not_includes Course.accessible_by(nil), @stu_course, "sitemap 等 nil 用户只出公开"
    assert_includes Course.accessible_by(@visitor), @public_course
    assert_not_includes Course.accessible_by(@visitor), @stu_course
    assert_includes Course.accessible_by(@student), @stu_course
    assert_not_includes Course.accessible_by(@student), @mem_course
    assert_includes Course.accessible_by(@member), @mem_course
    assert_includes Article.accessible_by(@student), @stu_article
    assert_not_includes Article.accessible_by(@student), @mem_article
  end

  test "章节/小节继承课程档位：会员课未标小节仅会员可见" do
    chapter = @mem_course.chapters.create!(title: "继承章", is_published: true)
    lesson = chapter.lessons.create!(title: "继承节", is_published: true)
    assert_equal User::TIER_MEMBER, lesson.effective_access_level
    assert_not lesson.available_to?(@student)
    assert lesson.available_to?(@member)
  end

  test "过期会员回落访客档" do
    @member.update!(member_expire_at: 1.day.ago)
    assert_not_predicate @member, :is_member?
    assert_equal User::TIER_VISITOR, @member.content_tier
  end

  test "学员身份展示与角色判断" do
    assert_predicate @student, :is_student?
    assert_not_predicate @student, :is_member?
    assert_equal "课程学员", @student.member_status
  end
end
