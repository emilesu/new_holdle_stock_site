# 订单过期清理
# 使用方法: rails orders:cleanup_expired
namespace :orders do
  desc "将超时未支付的订单标记为已过期"
  task cleanup_expired: :environment do
    expired = Order.pending.where("expire_at < ?", Time.current)
    count = expired.count
    expired.update_all(status: "expired")
    puts "已清理 #{count} 个过期订单"
  end
end
