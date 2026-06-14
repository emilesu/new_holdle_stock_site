module Admin
  class DashboardController < BaseController
    def index
      # 股票统计
      @a_stock_count = Stock.where(market: 'A股').count
      @us_stock_count = Stock.where(market: '美股').count
      @total_stocks = Stock.count
      
      # 用户统计
      @total_users = User.count
      @today_active_users = User.where(last_login_at: Date.today.all_day).count
      @week_active_users = User.where(last_login_at: 7.days.ago..Time.current).count
      @today_registered_users = User.where(created_at: Date.today.all_day).count
      
      # 会员统计
      @member_count = User.where(role: 'member').count
      @admin_count = User.where(role: 'admin').count + User.where(role: 'super_admin').count
      
      # 最近注册用户
      @recent_users = User.order(created_at: :desc).limit(5)
      
      # 最近股票
      @recent_stocks = Stock.order(created_at: :desc).limit(5)
    end
  end
end
