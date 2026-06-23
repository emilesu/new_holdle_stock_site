module TimeHelper
  BEIJING_TIME_ZONE = "Asia/Shanghai"

  def beijing_time(time = nil)
    time.present? ? time.in_time_zone(BEIJING_TIME_ZONE) : Time.current
  end

  def beijing_date(date = nil)
    date.present? ? date.in_time_zone(BEIJING_TIME_ZONE).to_date : Date.current
  end

  def format_beijing_time(time, format = :long)
    return nil unless time.present?
    l time.in_time_zone(BEIJING_TIME_ZONE), format: format
  end

  def format_beijing_date(date, format = :default)
    return nil unless date.present?
    l date.in_time_zone(BEIJING_TIME_ZONE).to_date, format: format
  end

  def relative_time(time)
    return "暂无记录" unless time.present?
    distance = Time.current - time.in_time_zone(BEIJING_TIME_ZONE)
    case
    when distance < 1.minute then "刚刚"
    when distance < 1.hour then "#{(distance / 1.minute).round} 分钟前"
    when distance < 1.day then "#{(distance / 1.hour).round} 小时前"
    when distance < 7.days then "#{(distance / 1.day).round} 天前"
    else l time.in_time_zone(BEIJING_TIME_ZONE), format: :short
    end
  end
end