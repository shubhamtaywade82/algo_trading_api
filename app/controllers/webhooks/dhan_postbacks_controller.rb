module Webhooks
  class DhanPostbacksController < ApplicationController
    # skip_before_action :verify_authenticity_token

    def create
      payload = request.raw_post
      data = JSON.parse(payload).with_indifferent_access

      Rails.logger.info "[DhanPostback] Received: #{data}"

      # Dhan::PostbackProcessor.call(data)
      Dhan::PostbackHandler.call(data)

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error "[DhanPostback] Invalid JSON: #{e.message}"
      head :bad_request
    end
  end
end
