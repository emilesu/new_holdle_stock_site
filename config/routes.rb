Rails.application.routes.draw do

  # Devise OAuth回调路由
  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }

  # OAuth失败跳转路由
  get '/users/oauth_failure', to: 'sessions#oauth_failure', as: :oauth_failure

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  resources :user_favorites, only: [:create, :destroy]

  resources :stocks, only: [:show] do
    member do
      get :radar_comparison
      get :indicator_detail
    end
    collection do
      get :autocomplete
    end
  end

  get "pyramid", to: "pyramids#index"
  get "pyramid/compare", to: "pyramids#compare"
  get "pyramid/update_sectors", to: "pyramids#update_sectors"
  get "pyramid/update_list", to: "pyramids#update_list"
  get "pyramid/load_more", to: "pyramids#load_more"

  resources :courses, only: [:index, :show]
  resources :lessons, only: [:show]

  get "join", to: "pages#join"

  # 前台登录用户留言
  resources :message_boards, only: [:create] do
    get :my, on: :collection
  end

  namespace :users do
    get "profile", to: "profiles#show", as: :profile
    get "profile/edit", to: "profiles#edit", as: :edit_profile
    patch "profile", to: "profiles#update"
    patch "profile/password", to: "profiles#update_password", as: :update_profile_password
    get "profile/favorites", to: "profiles#favorites", as: :profile_favorites
  end

  namespace :admin do
    root to: "dashboard#index"
    
    get "stock_crawlers", to: "stock_crawlers#index"
    get "stock_crawlers/us_stock_list", to: "stock_crawlers#us_stock_list"
    get "stock_crawlers/us_stock_basic", to: "stock_crawlers#us_stock_basic"
    get "stock_crawlers/us_finance", to: "stock_crawlers#us_finance"
    get "stock_crawlers/a_stock_list", to: "stock_crawlers#a_stock_list"
    get "stock_crawlers/a_finance", to: "stock_crawlers#a_finance"
    get "stock_crawlers/update_all_pyramid", to: "stock_crawlers#update_all_pyramid"
    get "stock_crawlers/refresh_all_radar", to: "stock_crawlers#refresh_all_radar"

    # 管理员后台留言管理
    resources :message_boards, only: [:index, :update, :destroy] do
      patch :reply, on: :member      # 回复留言
      patch :mark_read, on: :member  # 标记已读
      patch :restore, on: :member    # 恢复软删除留言
    end
    
    resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :stocks, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :recalculate_pyramid
      end
    end
    resources :courses do
      resources :chapters do
        resources :lessons
      end
    end
    # resources :payment_records, only: [:index, :show]  # 待开发
  end
end
