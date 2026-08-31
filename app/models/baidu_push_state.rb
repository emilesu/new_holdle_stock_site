# 百度推送当日配额状态（单例，id 恒为 1）。
# 超配额后当天剩余时间跳过推送，避免反复打无效请求 /  risking 降权。
class BaiduPushState < ApplicationRecord
  def self.singleton
    find_or_create_by!(id: 1) { |s| s.push_date = Date.current }
  end

  # 当天首次使用前重置跨天残留的配额/超配额状态
  def reset_if_new_day!
    return if push_date == Date.current
    update!(push_date: Date.current, remain: 0, over_quota: false)
  end
end