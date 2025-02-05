# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :options do
    post '/suggest_strategies', to: 'strategy_suggestions#index'
  end
  resources :mis_details
  namespace :webhooks do
    post :tradingview, to: 'alerts#create'
  end

  get '/funds', to: 'funds#index'
  get '/orders', to: 'orders#index'
  get '/orders/trades', to: 'orders#trades'
  get '/portfolio/holdings', to: 'portfolios#holdings'
  get '/portfolio/positions', to: 'portfolios#positions'
  get '/statements/ledger', to: 'statements#ledger'
  get '/statements/trade_history', to: 'statements#trade_history'

  resources :instruments, only: %i[index show]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
