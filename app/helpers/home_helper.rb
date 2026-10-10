# 首页 hero 网站简介视频配置：视频资源统一在此维护。
# 三个常量留空 = 视频未发布，页面显示「制作中」占位；填入后视图零改动自动上线。
module HomeHelper
  # 简介视频 BV 号（B站）。空字符串 = 视频未发布，播放按钮不渲染，「在 B站观看」按钮呈禁用态。
  HOME_VIDEO_BVID = ""

  # 简介视频封面图（16:9，图床 URL）。空 = 未提供，封面区显示「制作中」占位块。
  # 注意：站点为 HTTPS（assume_ssl + Nginx SSL 终结），图床必须使用 https:// 前缀，否则浏览器 mixed content 拦截。
  HOME_VIDEO_COVER_URL = ""

  # 简介视频 YouTube 地址（海外观众渠道）。空 = 未提供，按钮呈禁用态。
  HOME_VIDEO_YOUTUBE_URL = ""

  def home_video_bvid        = HOME_VIDEO_BVID
  def home_video_cover_url   = HOME_VIDEO_COVER_URL
  def home_video_youtube_url = HOME_VIDEO_YOUTUBE_URL
end
