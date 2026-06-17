Rails.application.routes.draw do
  devise_for :users

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

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
    
    resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy]
    resources :stocks, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      member do
        post :recalculate_pyramid
      end
    end
    # resources :courses, only: [:index, :new, :create, :edit, :update, :destroy]  # 待开发
    # resources :payment_records, only: [:index, :show]  # 待开发
  end
end
