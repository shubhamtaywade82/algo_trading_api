# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :auth do
    get 'dhan/login', to: 'dhan#login', as: :dhan_login
    get 'dhan/callback', to: 'dhan#callback', as: :dhan_callback
    get 'dhan/token', to: 'dhan#token', as: :dhan_token
  end

  resources :swing_picks
  namespace :options do
    post '/suggest_strategies', to: 'strategy_suggestions#index'
  end
  resources :mis_details
  namespace :webhooks do
    post :tradingview, to: 'alerts#create'
    post :dhan_postback, to: 'dhan_postbacks#create'
  end

  namespace :admin do
    resources :settings, only: %i[index update], param: :key
  end

  get '/funds', to: 'funds#index'
  get '/portfolio/holdings', to: 'portfolios#holdings'
  get '/portfolio/positions', to: 'portfolios#positions'
  get '/statements/ledger', to: 'statements#ledger'
  get '/statements/trade_history', to: 'statements#trade_history'
  get '/market_sentiment', to: 'market_sentiment#show'
  resources :options do
    collection do
      get :analysis
    end
  end

  namespace :openai do
    post 'chat', to: 'messages#create'
  end
  post 'telegram/webhook', to: 'telegram#webhook'

  resources :instruments, only: %i[index show]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  post 'mcp', to: 'mcp#handle'
  get 'mcp', to: 'mcp#handle'
  post 'mcp/debug', to: 'mcp#debug_handle'
  get 'mcp/debug', to: 'mcp#debug_handle'

  # AI Agents orchestration layer (analysis + proposals only, no execution)
  scope :ai_agents do
    post :analyze,        to: 'ai_agents#analyze'
    post :propose,        to: 'ai_agents#propose'
    post :ask,            to: 'ai_agents#ask'
    get  :positions,      to: 'ai_agents#positions'
    get  :session_report, to: 'ai_agents#session_report'
  end

  # Defines the root path route ("/")
  root to: proc { [200, { 'Content-Type' => 'application/json' }, ['{"status":"ok"}']] }
end
