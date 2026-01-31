# frozen_string_literal: true

module Dhan
  module Auth
    # STEP 3 of Dhan API key flow: exchange tokenId for access token and expiry.
    # See: https://auth.dhan.co/app/consumeApp-consent
    class ConsentConsumer
      BASE = 'https://auth.dhan.co'

      def self.call(token_id)
        new(token_id).call
      end

      def initialize(token_id)
        @token_id = token_id
      end

      def call
        raise 'DHAN_API_KEY and DHAN_API_SECRET are required' if app_id.blank? || app_secret.blank?

        response = get_consume_consent
        body = JSON.parse(response.body, symbolize_names: true)

        raise_consume_error(body) unless response.is_a?(Net::HTTPSuccess)

        {
          access_token: body[:accessToken] || body[:access_token],
          expires_at: parse_expiry(body[:expiryTime] || body[:expiry_time])
        }
      end

      private

      attr_reader :token_id

      def get_consume_consent
        uri = URI("#{BASE}/app/consumeApp-consent?tokenId=#{CGI.escape(token_id)}")
        req = Net::HTTP::Get.new(uri)
        req['app_id'] = app_id
        req['app_secret'] = app_secret

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      end

      def app_id
        ENV.fetch('DHAN_API_KEY', nil)
      end

      def app_secret
        ENV.fetch('DHAN_API_SECRET', nil)
      end

      def parse_expiry(expiry_time)
        return 24.hours.from_now if expiry_time.blank?

        Time.zone.parse(expiry_time.to_s)
      end

      def raise_consume_error(body)
        message = body[:message] || body[:error] || body.to_s
        raise "Dhan consent consume failed: #{message}"
      end
    end
  end
end
