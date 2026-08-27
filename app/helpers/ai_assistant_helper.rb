# AI 助手教程页配置：视频 / 截图资源统一在此维护。
# v1.39.0 起教程页已转正（preview/ai_assistant → 正式 /ai-assistant），本配置直接沿用。
module AiAssistantHelper
  # 宣传视频 BV 号（B站）。空字符串 = 视频未发布，页面显示「制作中」占位。
  AI_ASSISTANT_BVID = "BV1ZF8o6eE8P"

  # 宣传视频封面图（16:9，图床 URL）。空 = 未提供，页面显示「制作中」占位块。
  AI_ASSISTANT_COVER_URL = "https://video.holdle.com/image/default/95B29629FC6E4D00B3C4C42B5BF6C327-6-2.jpg"

  # 宣传视频 YouTube 地址（海外观众渠道）。空 = 未提供，按钮呈禁用态。
  AI_ASSISTANT_YOUTUBE_URL = "https://youtu.be/Ff4kyVRO7RI"

  # 安装方法 5 张截图（图床 URL，顺序对应 5 个步骤）。元素为空 = 该步骤显示「待补充截图」占位。
  # 注意：站点为 HTTPS（assume_ssl + Nginx SSL 终结），图床必须使用 https:// 前缀，否则浏览器 mixed content 拦截。
  AI_ASSISTANT_SCREENSHOTS = [
    "https://video.holdle.com/image/default/8D2890EF768740C7AC3A8FCCCF80FA6B-6-2.png", # 步骤 1 找到并点击「个人中心」
    "https://video.holdle.com/image/default/853F8F7E3A174E8B8ED7E7E5393E4811-6-2.png", # 步骤 2 复制「安装提示词」
    "https://video.holdle.com/image/default/F1203A6EBFDB4C6CA2EBCBDAD8E5EF98-6-2.png", # 步骤 3 粘贴给 AI，发送安装
    "https://video.holdle.com/image/default/EC6F98955CB44FA28EFAD228976CF1CE-6-2.png", # 步骤 4 输入问题，开始使用
    "https://video.holdle.com/image/default/BEAFD8880C3645AF9C54563C16D3B47C-6-2.png"  # 步骤 5 AI 生成回答
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
