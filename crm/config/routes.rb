Rails.application.routes.draw do
  root "dashboard#index"
  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  resources :contacts
  resources :accounts
  resources :deals
  resources :leads
  resources :activities

  get "/dashboard", to: "dashboard#index"
end
