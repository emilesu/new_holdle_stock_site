require "test_helper"

class Users::ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Plan.create!(plan_code: "welcome", name: "新用户体验", price_cents: 0, quota: 15)
  end

  def create_key(user, plain = "hl_testkey12345678")
    ApiKey.create!(
      user: user,
      key_hash: Digest::SHA256.hexdigest(plain),
      key_prefix: plain[0, 11],
      key_plaintext: plain,
      plan_code: "welcome",
      quota_remaining: 15,
      quota_total: 15
    )
  end

  test "登录用户可见完整 Key 明文" do
    user = users(:one)
    create_key(user)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "span[data-copy-target='source']", text: /hl_testkey12345678/
  end

  test "普通用户可见 Key、复制按钮与安装提示词（v1.39.0 起对所有用户开放）" do
    user = users(:one)
    create_key(user)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "button", text: "复制 Key"
    assert_select "button", text: "复制提示词"
    assert_select "textarea", /hl_testkey12345678/
    assert_select "textarea", %r{https://ai\.holdle\.com/mcp}
  end

  test "disabled key 不展示安装提示词（仅 active key 提供）" do
    user = users(:one)
    key = create_key(user)
    key.disable!
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "button", text: "复制 Key"
    assert_select "button", text: "复制提示词", count: 0
  end

  test "管理员可见安装提示词，提示词包含 Key 与新地址" do
    user = users(:two) # admin fixture
    create_key(user)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_select "button", text: "复制提示词"
    assert_select "textarea", /hl_testkey12345678/
    assert_select "textarea", %r{https://ai\.holdle\.com/mcp}
    # v1.2 使用规则段（MCP 强制路由 + round_id 计费说明）
    assert_select "textarea", /使用规则（必须遵守）/
    assert_select "textarea", /holdle_get_rules/
    assert_select "textarea", /round_id/
  end

  test "无 Key 用户显示购买引导" do
    user = users(:one)
    sign_in user

    get users_profile_path

    assert_response :success
    assert_match(/暂无 API Key/, response.body)
  end

  test "自助重新生成 Key：同 id 就地换新值，流水不断链" do
    user = users(:one)
    key = create_key(user)
    old_hash = key.key_hash
    old_id = key.id

    sign_in user
    post users_regenerate_api_key_path

    assert_redirected_to users_profile_path
    key.reload
    assert_equal old_id, key.id, "key id 不应变化"
    assert_not_equal old_hash, key.key_hash, "hash 应变化（旧 key 失效）"
    assert key.key_plaintext.present?, "应写入新明文"
    assert_match(/已重新生成/, flash[:notice])
  end

  test "无 active key 时自助重新生成给出提示" do
    user = users(:one)
    sign_in user

    post users_regenerate_api_key_path

    assert_redirected_to users_profile_path
    assert_match(/没有可重新生成的 Key/, flash[:alert])
  end

  test "未登录访问 profile 重定向到登录页" do
    get users_profile_path

    assert_redirected_to new_user_session_path
  end
end

# 收藏页（Users::ProfilesController#favorites）：搜索 / 筛选 / 排序 / 分组 / 会员墙 / 分页
class Users::ProfilesFavoritesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one) # 普通用户（非会员）
    @member = users(:two)
    @member.update!(role: "member", member_expire_at: 1.month.from_now)
  end

  def favorite(user, stock)
    UserFavorite.create!(user: user, stock: stock)
  end

  # 断言渲染出的收藏行恰好是给定股票
  def assert_rows(*expected)
    assert_select "[data-favorite-row]", count: expected.size
    expected.each { |stock| assert_select "#favorite_card_#{stock.id}", count: 1 }
  end

  def assert_order(*stocks)
    positions = stocks.map { |stock| response.body.index("id=\"favorite_card_#{stock.id}\"") }
    assert_equal positions.sort, positions, "行顺序不符合预期"
  end

  # ---------- 搜索 ----------

  test "按代码模糊搜索命中收藏" do
    favorite(@user, stocks(:two))
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path, params: { q: "0000" }

    assert_response :success
    assert_rows(stocks(:two))
  end

  test "搜索大小写不敏感" do
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path, params: { q: "aapl" }

    assert_rows(stocks(:one))
  end

  test "按中文名搜索" do
    favorite(@user, stocks(:two))
    favorite(@user, stocks(:four))
    sign_in @user

    get users_profile_favorites_path, params: { q: "平安" }

    assert_rows(stocks(:two))
  end

  test "按拼音首字母搜索（含美股 name 带竖线分支）" do
    favorite(@user, stocks(:two))
    favorite(@user, stocks(:five))
    sign_in @user

    get users_profile_favorites_path, params: { q: "payh" }
    assert_rows(stocks(:two))

    get users_profile_favorites_path, params: { q: "wr" }
    assert_rows(stocks(:five))
  end

  test "关键词超长时不过滤且不报错" do
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path, params: { q: "股" * 51 }

    assert_response :success
    assert_rows(stocks(:one))
  end

  test "关键词含通配符不误匹配" do
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path, params: { q: "%" }

    assert_response :success
    assert_select "[data-favorite-row]", count: 0
  end

  # ---------- 筛选 ----------

  test "按市场筛选，非法市场值被忽略" do
    favorite(@user, stocks(:two))
    favorite(@user, stocks(:three))
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path, params: { market: "CN" }
    assert_rows(stocks(:two), stocks(:three))

    get users_profile_favorites_path, params: { market: "XX" }
    assert_select "[data-favorite-row]", count: 3
  end

  test "按板块筛选，非法板块值被忽略" do
    liquor = Stock.create!(symbol: "TESTLQ", name: "测试白酒", market: "CN", sector: "白酒")
    favorite(@user, liquor)
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path, params: { sector: "白酒" }
    assert_rows(liquor)

    get users_profile_favorites_path, params: { sector: "不存在的板块" }
    assert_select "[data-favorite-row]", count: 2
  end

  test "板块下拉选项取该用户全部收藏的板块" do
    liquor = Stock.create!(symbol: "TESTLQ2", name: "测试白酒二", market: "CN", sector: "白酒")
    favorite(@user, liquor)
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path

    assert_select "#favorites-sector option[value='白酒']", count: 1
  end

  test "按评分区间筛选（会员）" do
    high = Stock.create!(symbol: "TESTHIGH", name: "高分股", market: "CN", pyramid_total_score: 88)
    low = Stock.create!(symbol: "TESTLOW", name: "低分股", market: "CN", pyramid_total_score: 0)
    favorite(@member, high)
    favorite(@member, low)
    sign_in @member

    get users_profile_favorites_path, params: { score_range: "80_100" }
    assert_rows(high)

    get users_profile_favorites_path, params: { score_range: "0_39" }
    assert_rows(low)
  end

  # ---------- 排序 ----------

  test "会员按金字塔评分排序" do
    high = Stock.create!(symbol: "TESTSH", name: "高分股B", market: "CN", pyramid_total_score: 88)
    low = Stock.create!(symbol: "TESTSL", name: "低分股B", market: "CN", pyramid_total_score: 11)
    favorite(@member, low)
    favorite(@member, high)
    sign_in @member

    get users_profile_favorites_path, params: { sort: "score" }

    assert_order(high, low)
  end

  test "非会员伪造评分排序参数被强制回退为最近收藏" do
    high = Stock.create!(symbol: "TESTSH2", name: "高分股C", market: "CN", pyramid_total_score: 88)
    low = Stock.create!(symbol: "TESTSL2", name: "低分股C", market: "CN", pyramid_total_score: 11)
    favorite(@user, low)
    favorite(@user, high)
    sign_in @user

    get users_profile_favorites_path, params: { sort: "score" }

    # 最近收藏在前（created_at 相同则由 id 稳定序兜底）
    assert_order(high, low)
  end

  # ---------- 分组 ----------

  test "按市场分组时分组顺序为 A股、港股、美股" do
    favorite(@user, stocks(:one))
    favorite(@user, stocks(:two))
    favorite(@user, stocks(:four))
    sign_in @user

    get users_profile_favorites_path, params: { group: "market" }

    markets = css_select("div[data-market-group]").map { |el| el["data-market-group"] }
    assert_equal %w[CN HK US], markets
  end

  test "按市场分组同时筛选市场时只出现该市场分组" do
    favorite(@user, stocks(:one))
    favorite(@user, stocks(:two))
    sign_in @user

    get users_profile_favorites_path, params: { group: "market", market: "CN" }

    assert_equal %w[CN], css_select("div[data-market-group]").map { |el| el["data-market-group"] }
  end

  # ---------- 会员墙 ----------

  test "非会员页面不渲染金字塔分数" do
    favorite(@user, Stock.create!(symbol: "TESTSC1", name: "分数不可见", market: "CN", pyramid_total_score: 88))
    sign_in @user

    get users_profile_favorites_path

    assert_response :success
    assert_select "[data-pyramid-score]", count: 0
  end

  test "会员页面渲染金字塔分数" do
    favorite(@member, Stock.create!(symbol: "TESTSC2", name: "分数可见", market: "CN", pyramid_total_score: 88))
    sign_in @member

    get users_profile_favorites_path

    assert_select "[data-pyramid-score]", count: 1
  end

  # ---------- 分页 ----------

  test "超过一页时分页且分页链接携带筛选参数" do
    21.times { |i| favorite(@user, Stock.create!(symbol: "TESTPG#{i}", name: "分页股#{i}", market: "CN")) }
    sign_in @user

    get users_profile_favorites_path, params: { market: "CN" }

    assert_response :success
    assert_select "[data-favorite-row]", count: 20
    assert_select "a[href*='market=CN']", minimum: 1
  end

  test "非法页码不报错" do
    favorite(@user, stocks(:one))
    sign_in @user

    ["0", "abc", "9999"].each do |page|
      get users_profile_favorites_path, params: { page: page }
      assert_response :success, "page=#{page} 应正常返回"
    end
  end

  # ---------- 空态 ----------

  test "无收藏与筛选无结果分别给出对应空态文案" do
    sign_in @user

    get users_profile_favorites_path
    assert_select "p", text: "暂无收藏的股票"

    favorite(@user, stocks(:one))
    get users_profile_favorites_path, params: { q: "不存在的关键词" }
    assert_select "p", text: "没有符合条件的收藏"
    assert_select "[data-favorite-row]", count: 0
  end

  # ---------- Stimulus / Turbo 接线 ----------

  test "收藏页的控制器、Stimulus 目标与 Turbo Frame 接线齐备" do
    favorite(@user, stocks(:one))
    sign_in @user

    get users_profile_favorites_path

    assert_response :success
    assert_select "[data-controller='favorites']", count: 1
    assert_select "turbo-frame#favorites_results", count: 1
    # 输入即搜依赖：表单（在 frame 外）指向 frame，输入框带防抖提交动作
    assert_select "form[data-turbo-frame='favorites_results']", count: 1
    assert_select "input#favorites-query[data-action*='favorites#search']", count: 1
    assert_select "input#favorites-query[name='q']", count: 1
    # 控制器读取的每个 target 都必须存在，否则 JS 会在交互时报错
    %w[form query groupInput groupButton results loadingHint].each do |target|
      assert_select "[data-favorites-target='#{target}']", { minimum: 1 }, "缺少 Stimulus 目标 #{target}"
    end
    assert_select "button[data-favorites-target='groupButton'][aria-pressed]", count: 1
    # frame 内分页链接由 Turbo 自动以自身为导航目标
    assert_select "turbo-frame#favorites_results a[href]", minimum: 1
  end

  # ---------- 入口 ----------

  test "个人中心与导航栏均提供收藏页入口" do
    sign_in @user

    get users_profile_path

    assert_response :success
    assert_select "a[href=?]", users_profile_favorites_path, minimum: 2
  end

  test "未登录访问收藏页重定向到登录页" do
    get users_profile_favorites_path

    assert_redirected_to new_user_session_path
  end
end
