# 加入会员页（/join）hero 视频配置：视频资源统一在此维护（与 HomeHelper / AiAssistantHelper 同模式）。
# 更换视频/封面时只改常量，视图零改动。
module PagesHelper
  # 会员介绍视频 MP4 直链（video-player 控制器按 .mp4 后缀注入原生 <video> 播放）。
  # 注意：站点为 HTTPS（assume_ssl + Nginx SSL 终结），必须使用 https:// 前缀，否则浏览器 mixed content 拦截。
  JOIN_VIDEO_URL = "https://video.holdle.com/b069aae7cdf671f1b1a35017f0e90102/48da209628b54b059592ca09ef109a9c-7ba388ebf6a35577aebe22cf43484013-hd.mp4"

  # 会员介绍视频封面图（16:9，图床 URL）。
  JOIN_VIDEO_COVER_URL = "https://video.holdle.com/image/default/6875539B74C4498896A0E843FC42000C-6-2.jpeg"

  def join_video_url        = JOIN_VIDEO_URL
  def join_video_cover_url  = JOIN_VIDEO_COVER_URL
end
