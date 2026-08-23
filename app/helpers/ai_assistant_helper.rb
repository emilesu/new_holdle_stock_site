# AI 助手教程页配置：视频 / 截图资源统一在此维护。
# 转正（preview/ai_assistant → 正式 /ai-assistant）后视图迁移，本配置直接沿用。
module AiAssistantHelper
  # 宣传视频 BV 号（B站）。空字符串 = 视频未发布，页面显示「制作中」占位。
  # 视频发布后由运营填入，无需改版。示例：AI_ASSISTANT_BVID = "BV1xx411c7mD"
  AI_ASSISTANT_BVID = ""

  # 宣传视频封面图（16:9，图床 URL）。空 = 未提供，页面显示「制作中」占位块。
  AI_ASSISTANT_COVER_URL = ""

  # 宣传视频 YouTube 地址（海外观众渠道）。空 = 未提供，按钮呈禁用态。
  AI_ASSISTANT_YOUTUBE_URL = ""

  # 安装方法 5 张截图（图床 URL，顺序对应 5 个步骤）。元素为空 = 该步骤显示「待补充截图」占位。
  AI_ASSISTANT_SCREENSHOTS = [
    "", # 步骤 1 找到并点击「个人中心」
    "", # 步骤 2 复制「安装提示词」
    "", # 步骤 3 粘贴给 AI，发送安装
    "", # 步骤 4 输入问题，开始使用
    ""  # 步骤 5 AI 生成回答
  ].freeze

  def ai_assistant_bvid
    AI_ASSISTANT_BVID
  end

  def ai_assistant_cover_url
    AI_ASSISTANT_COVER_URL
  end

  def ai_assistant_youtube_url
    AI_ASSISTANT_YOUTUBE_URL
  end

  # 第 index 步截图 URL（index 从 0 开始），空字符串返回 nil
  def ai_assistant_screenshot_url(index)
    url = AI_ASSISTANT_SCREENSHOTS[index].to_s.strip
    url.presence
  end
end
