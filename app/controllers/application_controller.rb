# frozen_string_literal: true

class ApplicationController < ActionController::API
  rescue_from StandardError, with: :handle_internal_error

  private

  def handle_internal_error(exception)
    ErrorLogger.log_error('Internal server error', exception)
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end
end
