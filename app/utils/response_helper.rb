# frozen_string_literal: true

module ResponseHelper
  def self.error_response(message, status = :unprocessable_entity)
    { error: { message: message, status: Rack::Utils.status_code(status) } }
  end

  def self.success_response(data, status = :ok)
    { data: data, status: Rack::Utils.status_code(status) }
  end
end
