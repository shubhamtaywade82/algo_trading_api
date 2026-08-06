# frozen_string_literal: true

class ApplicationController < ActionController::API
  # Set TOKEN_PROVIDER_ONLY=true to run this deployment as a bare Dhan token
  # provider: every controller except Auth::DhanController (token issuance,
  # login/callback) is shut off. Dhan::TokenManager's boot-time refresh and
  # background refresh thread (config/initializers/dhan_token_bootstrap.rb,
  # dhan_token_scheduler.rb) are untouched by this flag and keep running so the
  # token stays fresh for callers.
  TOKEN_PROVIDER_ALLOWED_CONTROLLERS = %w[Auth::DhanController].freeze

  before_action :enforce_token_provider_mode

  rescue_from StandardError, with: :handle_internal_error

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: e.message }, status: :not_found
  end

  private

  def enforce_token_provider_mode
    return unless ENV['TOKEN_PROVIDER_ONLY'] == 'true'
    return if TOKEN_PROVIDER_ALLOWED_CONTROLLERS.include?(self.class.name)

    render json: { error: 'This instance runs in token-provider-only mode; trading endpoints are disabled.' },
           status: :service_unavailable
  end

  def handle_internal_error(exception)
    ErrorLogger.log_error('Internal server error', exception)
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end
end
