Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  # 爬虫管理后台
  namespace :admin do
    get "stock_crawlers", to: "stock_crawlers#index"
    get "stock_crawlers/us_stock_list", to: "stock_crawlers#us_stock_list"
    get "stock_crawlers/us_stock_basic", to: "stock_crawlers#us_stock_basic"
    get "stock_crawlers/us_finance", to: "stock_crawlers#us_finance"
    get "stock_crawlers/a_stock_list", to: "stock_crawlers#a_stock_list"
    get "stock_crawlers/a_finance", to: "stock_crawlers#a_finance"
  end
end