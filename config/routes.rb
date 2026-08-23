Rails.application.routes.draw do

  # Devise OAuth回调路由
  devise_for :users, controllers: { registrations: 'users/registrations', omniauth_callbacks: 'users/omniauth_callbacks' }

  # OAuth失败跳转路由
  get '/users/oauth_failure', to: 'sessions#oauth_failure', as: :oauth_failure

  # B站数据API回调地址
  match '/oauth/callback', to: 'bilibili/callbacks#create', via: [:get, :post], as: :bilibili_callback

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
  get "pyramid/update_industries", to: "pyramids#update_industries"
  get "pyramid/update_list", to: "pyramids#update_list"
  get "pyramid/load_more", to: "pyramids#load_more"
  get "pyramid/permission", to: "pyramids#permission"

  resources :courses, only: [:index, :show]
  resources :lessons, only: [:show]
  resources :articles, only: [:index, :show]

  get "join", to: "pages#join"

  # 注册引导（新用户首次注册后进入；admin 可 ?preview=1 预览）
  get "onboarding", to: "onboardings#show", as: :onboarding
  post "onboarding/complete", to: "onboardings#complete", as: :onboarding_complete

  # 服务协议 / 隐私政策（公开静态页）
  get "terms", to: "legal#terms"
  get "privacy", to: "legal#privacy"

  # 暗发布预览：新页面重设计，仅 admin 可见（非 admin 404），确认后删除
  namespace :preview do
    get :home
    get :join
    get :plans
  end
  get "video", to: "pages#video"
  get "about", to: "pages#about"

  # 微信支付订单
  resources :orders, only: [:new, :create, :show] do
    member do
      get :status
    end
  end

  # 微信支付回调
  namespace :wechat do
    post "pay_callbacks", to: "pay_callbacks#create"
  end

  # T7 计费后台：MCP 服务三步扣次接口（内部 token 鉴权，见 03_T7计费后台设计_v0.2.md）
  namespace :api do
    namespace :v1 do
      namespace :mcp do
        post :precheck
        post :confirm
        post :release
      end
    end
  end

  # 前台登录用户留言
  resources :message_boards, only: [:create] do
    get :my, on: :collection
  end

  namespace :users do
    get "profile", to: "profiles#show", as: :profile
    post "profile/regenerate_api_key", to: "profiles#regenerate_api_key", as: :regenerate_api_key
    get "profile/edit", to: "profiles#edit", as: :edit_profile
    patch "profile", to: "profiles#update"
    patch "profile/password", to: "profiles#update_password", as: :update_profile_password
    get "profile/favorites", to: "profiles#favorites", as: :profile_favorites
  end

  namespace :admin do
    root to: "dashboard#index"
    
    get "stock_crawlers", to: "stock_crawlers#index"
    post "stock_crawlers/us_stock_list", to: "stock_crawlers#us_stock_list"
    post "stock_crawlers/us_stock_basic", to: "stock_crawlers#us_stock_basic"
    post "stock_crawlers/us_finance", to: "stock_crawlers#us_finance"
    post "stock_crawlers/us_finance_em", to: "stock_crawlers#us_finance_em"
    post "stock_crawlers/us_finance_em_single", to: "stock_crawlers#us_finance_em_single"
    post "stock_crawlers/a_stock_list", to: "stock_crawlers#a_stock_list"
    post "stock_crawlers/a_finance", to: "stock_crawlers#a_finance"
    post "stock_crawlers/a_finance_em", to: "stock_crawlers#a_finance_em"
    post "stock_crawlers/a_finance_em_single", to: "stock_crawlers#a_finance_em_single"
    post "stock_crawlers/update_all_pyramid", to: "stock_crawlers#update_all_pyramid"
    post "stock_crawlers/refresh_all_radar", to: "stock_crawlers#refresh_all_radar"
    post "stock_crawlers/refresh_all_radar_full", to: "stock_crawlers#refresh_all_radar_full"
    post "stock_crawlers/hk_stock_list", to: "stock_crawlers#hk_stock_list"
    post "stock_crawlers/hk_finance", to: "stock_crawlers#hk_finance"
    post "stock_crawlers/hk_finance_em", to: "stock_crawlers#hk_finance_em"
    post "stock_crawlers/hk_finance_em_single", to: "stock_crawlers#hk_finance_em_single"

    # 管理员后台留言管理
    resources :message_boards, only: [:index, :update, :destroy] do
      patch :reply, on: :member      # 回复留言
      patch :mark_read, on: :member  # 标记已读
      patch :restore, on: :member    # 恢复软删除留言
    end
    
    resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :adjust_api_key_quota  # 调整 key 次数（补偿）
        post :disable_api_key       # 停用 key
        post :enable_api_key        # 启用 key
        post :regenerate_api_key    # 重新生成 key
      end
    end

    # T7 Phase2：套餐只读
    resources :plans, only: [:index]

    # T7 Phase3：AI 提问分析报表（只读）
    get "usage_analytics", to: "usage_analytics#index"
    resources :stocks, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      collection do
        get :sectors
      end
      member do
        post :recalculate_pyramid
      end
    end
    resources :courses do
      resources :chapters do
        resources :lessons
      end
    end
    resources :articles

    # 后台订单管理
    resources :orders, only: [:index, :show]

    # resources :payment_records, only: [:index, :show]  # 待开发
  end
end
