# 百度主动推送异步任务（SolidQueue 队列）
class BaiduPushJob < ApplicationJob
  queue_as :default

  def perform(urls)
    BaiduPushService.push(urls)
  end
end